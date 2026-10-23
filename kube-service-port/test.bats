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

stub_cluster() {
    printf '#!/bin/sh\nif [ "$3" = get ]; then echo '"'"'{"spec":{"ports":[{"name":"http","port":80},{"name":"https","port":443}]}}'"'"'; else echo "kubectl $*" >>"%s"; fi\n' "$CALLS" | stub_script kubectl
}

@test "kube-service-port is installed on PATH and syntactically valid" {
    command -v kube-service-port
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-service-port errors with missing arguments" {
    run kube-service-port ns svc https
    [ "$status" -ne 0 ]
}

@test "kube-service-port patches the named port" {
    stub_cluster
    run kube-service-port cattle-system rancher https 7083
    [ "$status" -eq 0 ]
    grep -q '"path":"/spec/ports/1/port","value":7083' "$CALLS"
}

@test "kube-service-port leaves the Service alone when the port name is unknown" {
    stub_cluster
    run kube-service-port cattle-system rancher nope 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"no port named 'nope'"* ]]
    [ ! -s "$CALLS" ]
}
