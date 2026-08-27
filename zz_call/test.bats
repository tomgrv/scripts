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

@test "zz_call prompts, persists, and an input entry's own 'as' renames the eval'd output" {
    run bash -c 'printf "myhost\nsecret123\n" | zz_call'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='myhost'"* ]]
    [[ "$output" == *"export PGPASSWORD='secret123'"* ]]
    grep -q '^DB_HOST=myhost$' .env
    grep -q '^DB_PASSWORD=secret123$' .env
}

@test "zz_call does not prompt or persist when vars are already set" {
    run env DB_HOST=envhost DB_PASSWORD=envpass zz_call
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='envhost'"* ]]
    [[ "$output" == *"export PGPASSWORD='envpass'"* ]]
    [ ! -f .env ]
}

@test "zz_call runs the wrapped command, exporting both var and its 'as' alias" {
    run bash -c 'printf "cmdhost\ncmdpass\n" | zz_call sh -c "echo DB_HOST=\$DB_HOST DB_PASSWORD=\$DB_PASSWORD PGPASSWORD=\$PGPASSWORD"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DB_HOST=cmdhost DB_PASSWORD=cmdpass PGPASSWORD=cmdpass"* ]]
}

@test "zz_call an explicit output array filters which vars are printed" {
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
    run bash -c 'printf "myhost\nsecret123\n" | zz_call'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export DB_HOST='myhost'"* ]]
    [[ "$output" != *"export DB_PASSWORD="* ]]
}

@test "zz_call errors without a package.json" {
    rm -f package.json
    run zz_call
    [ "$status" -ne 0 ]
}
