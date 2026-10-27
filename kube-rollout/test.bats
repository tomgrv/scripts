#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    CALLS="$WORK/calls"
    : >"$CALLS"
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

# stub_rollout <rollout exit code>: record every kubectl call, fake kube-diagnose.
stub_rollout() {
    printf '#!/bin/sh\necho "kubectl $*" >>"%s"\n[ "$3" = rollout ] && exit %s\nexit 0\n' "$CALLS" "$1" | stub_script kubectl
    printf '#!/bin/sh\necho "diagnose $*" >>"%s"\n' "$CALLS" | stub_script kube-diagnose
}

@test "kube-rollout is installed on PATH and syntactically valid" {
    command -v kube-rollout
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-rollout errors without a namespace and a deployment" {
    run kube-rollout ns
    [ "$status" -ne 0 ]
}

@test "kube-rollout waits for the rollout with the timeout and stays quiet on success" {
    stub_rollout 0
    run kube-rollout -t 2m coder coder
    [ "$status" -eq 0 ]
    grep -q '^kubectl -n coder rollout status deploy/coder --timeout 2m$' "$CALLS"
    ! grep -q '^diagnose' "$CALLS"
}

@test "kube-rollout diagnoses and fails when the rollout does not finish, or only warns with -w" {
    stub_rollout 1
    run kube-rollout coder coder
    [ "$status" -eq 1 ]
    grep -q '^diagnose coder$' "$CALLS"
    run kube-rollout -w coder coder
    [ "$status" -eq 0 ]
    [[ "$output" == *"did not become ready"* ]]
}
