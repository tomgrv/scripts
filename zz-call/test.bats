#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    cat > package.json <<'EOF'
{
  "config": {
    "input": [
      {"var": "DB_HOST", "question": "Database host?", "default": "localhost"},
      {"var": "DB_PASSWORD", "question": "Database password?", "as": "PGPASSWORD"}
    ]
  }
}
EOF
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "zz-call is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-call)"
    [ "$status" -eq 0 ]
}

@test "zz-call prompts, persists, and an input entry's own 'as' renames the eval'd output" {
    run bash -c 'printf "myhost\nsecret123\n" | zz-call'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='myhost'"* ]]
    [[ "$output" == *"export PGPASSWORD='secret123'"* ]]
    grep -q '^DB_HOST=myhost$' .env
    grep -q '^DB_PASSWORD=secret123$' .env
}

@test "zz-call does not prompt or persist when vars are already set" {
    run env DB_HOST=envhost DB_PASSWORD=envpass zz-call
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='envhost'"* ]]
    [[ "$output" == *"export PGPASSWORD='envpass'"* ]]
    [ ! -f .env ]
}

@test "zz-call runs the wrapped command, exporting both var and its 'as' alias" {
    run bash -c 'printf "cmdhost\ncmdpass\n" | zz-call sh -c "echo DB_HOST=\$DB_HOST DB_PASSWORD=\$DB_PASSWORD PGPASSWORD=\$PGPASSWORD"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DB_HOST=cmdhost DB_PASSWORD=cmdpass PGPASSWORD=cmdpass"* ]]
}

@test "zz-call an explicit output array filters which vars are printed" {
    cat > package.json <<'EOF'
{
  "config": {
    "input": [
      {"var": "DB_HOST", "question": "Database host?", "default": "localhost"},
      {"var": "DB_PASSWORD", "question": "Database password?"}
    ],
    "output": [{"var": "DB_HOST"}]
  }
}
EOF
    run bash -c 'printf "myhost\nsecret123\n" | zz-call'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='myhost'"* ]]
    [[ "$output" != *"export DB_PASSWORD="* ]]
}

@test "zz-call errors without a package.json" {
    rm -f package.json
    run zz-call
    [ "$status" -ne 0 ]
}

@test "zz-call uses default for a missing var and persists that default when accepted" {
    run bash -c 'printf "\nsecret123\n" | zz-call'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='localhost'"* ]]
    grep -q '^DB_HOST=localhost$' .env
}

@test "zz-call -p points to a non-default package.json path" {
    mkdir -p sub
    cat > sub/other.json <<'EOF'
{
  "config": {
    "input": [{"var": "SOME_VAR", "question": "Value?", "default": "x"}]
  }
}
EOF
    run bash -c 'printf "picked\n" | zz-call -p sub/other.json'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export SOME_VAR='picked'"* ]]
}

@test "zz-call reads config.file to choose a non-.env persistence target" {
    cat > package.json <<'EOF'
{
  "config": {
    "file": "custom.env",
    "input": [{"var": "DB_HOST", "question": "Host?", "default": "localhost"}]
  }
}
EOF
    run bash -c 'printf "myhost\n" | zz-call'
    [ "$status" -eq 0 ]
    [ -f custom.env ]
    grep -q '^DB_HOST=myhost$' custom.env
    [ ! -f .env ]
}

@test "zz-call reads vps.inputs from several package.json files (first definition wins)" {
    cat > a.json <<'EOF'
{"vps": {"inputs": {"A_VAR": {"description": "A?", "default": "adef"}, "SHARED": {"default": "first"}}}}
EOF
    cat > b.json <<'EOF'
{"vps": {"inputs": {"B_VAR": {"default": "bdef"}, "SHARED": {"default": "second"}}}}
EOF
    run zz-call -n -p a.json:b.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"export A_VAR='adef'"* ]]
    [[ "$output" == *"export B_VAR='bdef'"* ]]
    [[ "$output" == *"export SHARED='first'"* ]]
}

@test "zz-call -n never prompts or persists defaults" {
    run zz-call -n
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='localhost'"* ]]
    [ ! -f .env ]
}

@test "zz-call reads a persisted value literally from the env file instead of prompting" {
    echo 'DB_HOST=$(touch pwned)' >.env
    run env DB_PASSWORD=p zz-call
    [ "$status" -eq 0 ]
    [[ "$output" == *'export DB_HOST='"'"'$(touch pwned)'"'"* ]]
    [ ! -e pwned ]
}

@test "zz-call -f chooses the env file and -e persists values already in the environment" {
    run env DB_HOST="my host" DB_PASSWORD=p zz-call -e -f custom.env
    [ "$status" -eq 0 ]
    grep -qx 'DB_HOST=my host' custom.env
    grep -qx 'DB_PASSWORD=p' custom.env
    [ "$(stat -c %a custom.env)" = 600 ]
}

@test "zz-call -P also exports persisted values from a profile.d snippet" {
    name=zz-call-test-$$
    run env DB_HOST="a b" DB_PASSWORD=p zz-call -e -P "$name"
    [ "$status" -eq 0 ]
    # /etc/profile.d is not configurable and not writable without root (CI).
    if [ -f "/etc/profile.d/$name.sh" ]; then
        grep -qx "export DB_HOST='a b'" "/etc/profile.d/$name.sh"
    fi
    rm -f "/etc/profile.d/$name.sh"
}

@test "zz-call persists a secret input through zz-persist into an owner-only file" {
    cat > package.json <<'EOF'
{"vps": {"inputs": {"TOK": {"description": "Token", "secret": true, "default": "dflt"}}}}
EOF
    run zz-call </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"export TOK='dflt'"* ]]
    grep -qx 'TOK=dflt' .env
    [ "$(stat -c %a .env)" = 600 ]
}
