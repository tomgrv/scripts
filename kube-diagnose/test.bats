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

@test "kube-diagnose is installed on PATH and syntactically valid" {
    command -v kube-diagnose
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-diagnose errors without a namespace" {
    run kube-diagnose
    [ "$status" -ne 0 ]
}

@test "kube-diagnose shows pods, events, and why an unready pod or a ServiceLB pod is stuck" {
    stub_script kubectl <<'STUB'
#!/bin/sh
case "$*" in
  *"-n kube-system get pods --no-headers"*) echo "svclb-rancher-abc 0/2 Pending 0 1m" ;;
  *"-n cattle-system get pods --no-headers"*) echo "rancher-1 0/1 ContainerCreating 0 1m" ;;
  *"describe pod"*) printf 'Name: x\nEvents:\n  Warning  FailedScheduling  node(s) did not have free ports for the requested pod ports\n' ;;
  *"get events"*) echo "5s Warning FailedScheduling pod/svclb-rancher-abc no free ports" ;;
  *) echo "kubectl $*" ;;
esac
STUB
    run kube-diagnose cattle-system
    [ "$status" -eq 0 ]
    [[ "$output" == *"diagnostics for namespace cattle-system"* ]]
    [[ "$output" == *"FailedScheduling"* ]]
    [[ "$output" == *"free ports"* ]]
    [[ "$output" == *"end of diagnostics"* ]]
}
