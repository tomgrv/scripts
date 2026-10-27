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

# stub_helm <exit code of "repo add">
stub_helm() {
    printf '#!/bin/sh\necho "helm $*" >>"%s"\n[ "$2" = add ] && exit %s\nexit 0\n' "$CALLS" "$1" | stub_script helm
}

@test "helm-repo is installed on PATH and syntactically valid" {
    command -v helm-repo
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "helm-repo needs name/url pairs" {
    run helm-repo bitnami
    [ "$status" -ne 0 ]
}

@test "helm-repo adds every repository with --force-update, then refreshes them once" {
    stub_helm 0
    run helm-repo bitnami https://charts.bitnami.com/bitnami jetstack https://charts.jetstack.io
    [ "$status" -eq 0 ]
    grep -qx 'helm repo add bitnami https://charts.bitnami.com/bitnami --force-update' "$CALLS"
    grep -qx 'helm repo add jetstack https://charts.jetstack.io --force-update' "$CALLS"
    grep -qx 'helm repo update bitnami jetstack' "$CALLS"
}

@test "helm-repo rejects a non-http URL and names the URL when the add fails" {
    stub_helm 0
    run helm-repo x ftp://nope
    [ "$status" -ne 0 ]
    stub_helm 1
    run helm-repo x https://charts.example.com
    [ "$status" -ne 0 ]
    [[ "$output" == *"https://charts.example.com"* ]]
}
