#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
}

teardown() {
    rm -rf "$WORK"
    teardown_scripts_path
}

# no_kube_path: a PATH holding the scripts and every system tool except kubectl and helm
# (a CI runner ships both), so "missing" is real.
no_kube_path() {
    mkdir -p "$WORK/nokube"
    local f
    for f in /usr/bin/* /bin/*; do
        case "$(basename "$f")" in kubectl | helm) continue ;; esac
        ln -sf "$f" "$WORK/nokube/$(basename "$f")" 2>/dev/null || true
    done
    printf '%s' "$TEST_BIN:$WORK/nokube"
}

@test "kube-require is installed on PATH and syntactically valid" {
    command -v kube-require
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "kube-require prints the KUBECONFIG export (default k3s path, KUBECONFIG, -k)" {
    printf '#!/bin/sh\n' | stub_script kubectl
    printf '#!/bin/sh\necho v3.17.4\n' | stub_script helm
    run env -u KUBECONFIG sh -c 'kube-require 2>/dev/null'
    [ "$output" = "export KUBECONFIG='/etc/rancher/k3s/k3s.yaml'" ]
    run env KUBECONFIG=/x/y sh -c 'kube-require 2>/dev/null'
    [ "$output" = "export KUBECONFIG='/x/y'" ]
    run sh -c 'kube-require -k /z 2>/dev/null'
    [ "$output" = "export KUBECONFIG='/z'" ]
}

@test "kube-require makes the caller exit 1 when kubectl or helm is missing" {
    printf '#!/bin/sh\n' | stub_script helm
    run env PATH="$(no_kube_path)" sh -c 'command -v kubectl && exit 9; eval "$(kube-require 2>/dev/null)"; echo not-reached'
    [ "$status" -eq 1 ]
    [[ "$output" != *"not-reached"* ]]
}

@test "kube-require -d makes the caller return 0 when kubectl is missing" {
    run env PATH="$(no_kube_path)" sh -c 'f() { eval "$(kube-require -d 2>/dev/null)"; echo not-reached; }; f; echo after'
    [ "$status" -eq 0 ]
    [[ "$output" == *"after"* ]]
    [[ "$output" != *"not-reached"* ]]
}

# stub_helm <version>: a helm that reports this version.
stub_helm() {
    printf '#!/bin/sh\necho v%s\n' "$1" | stub_script helm
    printf '#!/bin/sh\nexit 0\n' | stub_script kubectl
}

@test "kube-require -H: helm 3.17 or later passes, an older or missing one does not" {
    stub_helm 3.17.4
    run kube-require -H
    [ "$status" -eq 0 ]
    stub_helm 4.0.1
    run kube-require -H
    [ "$status" -eq 0 ]
    stub_helm 3.16.2
    run kube-require -H
    [ "$status" -eq 1 ]
    PATH="$(no_kube_path)" run kube-require -H
    [ "$status" -eq 1 ]
}

@test "kube-require makes the caller exit 1, saying why, when helm is too old" {
    stub_helm 3.16.2
    run kube-require
    [[ "$output" == *"too old"* ]]
    [[ "$output" == *"exit 1"* ]]
}
