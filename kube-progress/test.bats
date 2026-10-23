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

# stub_kubectl: two pods in the namespace, one ready, one still starting.
stub_kubectl() {
    stub_script kubectl <<'STUB'
#!/bin/sh
printf 'rancher-1   1/1   Running             0   1m\nrancher-2   0/1   ContainerCreating   0   5s\n'
STUB
}

@test "kube-progress is installed on PATH and syntactically valid" {
    command -v kube-progress
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-progress errors without a namespace, a label and a command" {
    run kube-progress
    [ "$status" -ne 0 ]
    run kube-progress ns label
    [ "$status" -ne 0 ]
}

@test "kube-progress logs elapsed time and pod states while the command runs, keeps its output" {
    stub_kubectl
    run kube-progress -i 1 cattle-system "Rancher install" sh -c 'sleep 3; echo done-output'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rancher install: 1s, 1/2 pods ready - waiting: rancher-2=ContainerCreating"* ]]
    [[ "$output" == *"done-output"* ]]
}

@test "kube-progress returns the command's exit status and stops reporting afterwards" {
    stub_kubectl
    run sh -c "kube-progress -i 1 ns label sh -c 'sleep 2; exit 7'; rc=\$?; sleep 2; echo rc=\$rc"
    [[ "$output" == *"rc=7"* ]]
    [ "$(printf '%s\n' "$output" | grep -c 'label: ')" -le 2 ]
}

@test "kube-progress says so when the namespace has no pod yet" {
    stub_script kubectl <<'STUB'
#!/bin/sh
exit 0
STUB
    run kube-progress -i 1 cattle-system "Rancher install" sleep 2
    [[ "$output" == *"no pod in cattle-system yet"* ]]
}
