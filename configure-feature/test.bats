#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    git commit -q --allow-empty -m "init"
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "configure-feature is installed on PATH and syntactically valid" {
    command -v configure-feature
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "configure-feature -h prints usage and exits non-zero" {
    run configure-feature -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "configure-feature errors without a feature argument" {
    run configure-feature
    [ "$status" -ne 0 ]
}

@test "configure-feature errors when the source directory does not exist" {
    run configure-feature -s "$WORK_DIR/nonexistent" myfeature
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "configure-feature copies a new plain-text stub file into the cwd" {
    mkdir -p src/stubs
    echo "line1" >src/stubs/plain.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/plain.txt" ]
    grep -q line1 "$WORK_DIR/plain.txt"
}

@test "configure-feature replaces a dangling destination symlink with the stub" {
    mkdir -p src/stubs/sub
    echo "line1" >src/stubs/sub/plain.md
    mkdir -p sub
    ln -s ../missing/plain.md sub/plain.md
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [[ "$output" == *"dangling symlink"* ]]
    [ ! -L sub/plain.md ]
    grep -q line1 sub/plain.md
}

@test "configure-feature merges a json stub into an existing json file" {
    mkdir -p src/stubs
    echo '{"b":2}' >src/stubs/config.json
    echo '{"a":1}' >config.json
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    result=$(cat config.json)
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
}

@test "configure-feature copies a json stub as-is when destination doesn't exist" {
    mkdir -p src/stubs
    echo '{"a":1}' >src/stubs/newfile.json
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f newfile.json ]
    grep -q '"a"' newfile.json
}

@test "configure-feature reconciles a fragment additively into an existing plain-text file" {
    mkdir -p src/stubs
    printf 'line1\nline2\n' >src/stubs/frag.txt
    printf 'existing1\n' >frag.txt

    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    grep -q existing1 frag.txt
    grep -q line1 frag.txt
    grep -q line2 frag.txt
}

@test "configure-feature replaces an existing file when the stub opens with frontmatter" {
    mkdir -p src/stubs
    printf -- '---\nname: skill\ndescription: d\n---\n\n# Skill\n' >src/stubs/SKILL.md
    printf '# Skill\n\nold body\n' >SKILL.md

    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(head -n1 SKILL.md)" = "---" ]
    cmp -s src/stubs/SKILL.md SKILL.md
}

@test "configure-feature strips a leading underscore prefix from stub filenames" {
    mkdir -p src/stubs
    echo "content" >src/stubs/_prefix.actual.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f actual.txt ]
    [ ! -f _prefix.actual.txt ]
}

@test "configure-feature adds hash-prefixed stub destinations to .gitignore" {
    mkdir -p src/stubs
    echo "secretcontent" >'src/stubs/#ignored.txt'
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f ignored.txt ]
    grep -qxF "./ignored.txt" .gitignore
}

@test "configure-feature preserves executable permission bits from stub source" {
    mkdir -p src/stubs
    printf '#!/bin/sh\necho hi\n' >src/stubs/exec.sh
    chmod 755 src/stubs/exec.sh
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -x exec.sh ]
}

@test "configure-feature deploys stub symlinks when the destination doesn't already exist" {
    mkdir -p src/stubs
    echo "target-content" >src/stubs/real.txt
    ln -s real.txt src/stubs/linked.txt
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -L linked.txt ]
}

@test "configure-feature .clean RMV untracks a file but keeps it on disk" {
    echo "legacy" >legacy.txt
    git add legacy.txt
    git commit -q -m "add legacy"

    mkdir -p src/stubs
    echo "RMV legacy.txt" >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f legacy.txt ]
    ! git ls-files --error-unmatch legacy.txt >/dev/null 2>&1
}

@test "configure-feature .clean DEL deletes a file and untracks it" {
    echo "obsolete" >obsolete.txt
    git add obsolete.txt
    git commit -q -m "add obsolete"

    mkdir -p src/stubs
    echo "DEL obsolete.txt" >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ ! -f obsolete.txt ]
    ! git ls-files --error-unmatch obsolete.txt >/dev/null 2>&1
}

@test "configure-feature .clean KEY removes a key from a JSON file" {
    cat >package.json <<'EOF'
{
    "name": "t",
    "lint-staged": {
        "old-glob.json": ["old"],
        "keep.json": ["keep"]
    }
}
EOF
    mkdir -p src/stubs
    echo 'KEY package.json ["lint-staged","old-glob.json"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(jq -r '."lint-staged" | has("old-glob.json")' package.json)" = "false" ]
    [ "$(jq -r '."lint-staged" | has("keep.json")' package.json)" = "true" ]
    [ "$(jq -r '.name' package.json)" = "t" ]
}

@test "configure-feature .clean KEY handles keys with glob characters and spaces in the path list" {
    cat >package.json <<'EOF'
{
    "lint-staged": {
        "!(*schema).json": ["normalize"],
        "*.php": ["lint"]
    }
}
EOF
    mkdir -p src/stubs
    printf '%s\n' 'KEY package.json ["lint-staged", "!(*schema).json"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(jq -r '."lint-staged" | keys | join(",")' package.json)" = "*.php" ]
}

@test "configure-feature .clean KEY is a no-op when the key or file is missing" {
    echo '{"a": 1}' >data.json
    cp data.json data.before
    mkdir -p src/stubs
    printf '%s\n' 'KEY data.json ["missing","key"]' 'KEY nofile.json ["a"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    cmp data.json data.before
    [ ! -f nofile.json ]
}

@test "configure-feature .clean KEY rejects a path that is not a JSON array and leaves the file alone" {
    echo '{"a": {"b": 1}}' >data.json
    cp data.json data.before
    mkdir -p src/stubs
    printf '%s\n' 'KEY data.json .a.b' 'KEY data.json []' 'KEY data.json' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    cmp data.json data.before
    [[ "$output" == *"Invalid"* ]]
}

@test "configure-feature .clean KEY skips a file that is not valid JSON" {
    printf '%s\n' '{ not json' >broken.json
    cp broken.json broken.before
    mkdir -p src/stubs
    printf '%s\n' 'KEY broken.json ["a"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    cmp broken.json broken.before
}

@test "configure-feature .clean KEY runs before the stub merge, so the stub's value replaces the old one" {
    mkdir -p src/stubs
    echo '{"keep": 1, "legacy": 2}' >src/stubs/data.json
    echo '{"legacy": 0}' >data.json
    echo 'KEY data.json ["legacy"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(jq -r '.keep' data.json)" = "1" ]
    [ "$(jq -r '.legacy' data.json)" = "2" ]
}

@test "configure-feature .clean KEY leaves a key gone when the stub no longer has it" {
    mkdir -p src/stubs
    echo '{"keep": 1}' >src/stubs/data.json
    echo '{"legacy": 0, "own": true}' >data.json
    echo 'KEY data.json ["legacy"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(jq -r 'has("legacy")' data.json)" = "false" ]
    [ "$(jq -r '.own' data.json)" = "true" ]
}

# --- YAML (needs mikefarah/yq, as merge-yaml does) -------------------------

require_mikefarah_yq() {
    yq --version 2>&1 | grep -q mikefarah || skip "needs mikefarah/yq"
}

@test "configure-feature .clean KEY replaces a scalar in a YAML file with the stub's value" {
    require_mikefarah_yq
    cat >wf.yml <<'EOF'
# consumer workflow
jobs:
  review:
    if: old-gate # keep this comment
    runs-on: ubuntu-latest
EOF
    mkdir -p src/stubs
    cat >src/stubs/wf.yml <<'EOF'
jobs:
  review:
    if: new-gate
    runs-on: ubuntu-latest
EOF
    echo 'KEY wf.yml ["jobs","review","if"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(yq '.jobs.review.if' wf.yml)" = "new-gate" ]
    grep -q "# consumer workflow" wf.yml
}

@test "configure-feature .clean KEY fixes a broken scalar inside a list element selected by name" {
    require_mikefarah_yq
    cat >wf.yml <<'EOF'
jobs:
  sync:
    steps:
      - name: Other step
        with:
          repository: untouched
      - name: Create pull request
        with:
          repository: org/{{ matrix.name }}
          keep: me
EOF
    mkdir -p src/stubs
    cat >src/stubs/wf.yml <<'EOF'
jobs:
  sync:
    steps:
      - name: Create pull request
        with:
          repository: org/${{ matrix.name }}
EOF
    cat >src/stubs/.clean <<'EOF'
KEY wf.yml ["jobs","sync","steps",{"name":"Create pull request"},"with","repository"]
EOF
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(yq '.jobs.sync.steps[1].with.repository' wf.yml)" = 'org/${{ matrix.name }}' ]
    [ "$(yq '.jobs.sync.steps[1].with.keep' wf.yml)" = "me" ]
    [ "$(yq '.jobs.sync.steps[0].with.repository' wf.yml)" = "untouched" ]
}

@test "configure-feature .clean KEY removes a YAML key so the merge cannot leave two exclusive triggers" {
    require_mikefarah_yq
    cat >wf.yml <<'EOF'
on:
  push:
    paths:
      - old/**
EOF
    mkdir -p src/stubs
    cat >src/stubs/wf.yml <<'EOF'
on:
  push:
    paths-ignore:
      - '**/*.md'
EOF
    echo 'KEY wf.yml ["on","push","paths"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(yq '.on.push | has("paths")' wf.yml)" = "false" ]
    [ "$(yq '.on.push | has("paths-ignore")' wf.yml)" = "true" ]
}

@test "configure-feature .clean KEY is a no-op when a name selector or index does not resolve" {
    require_mikefarah_yq
    cat >wf.yml <<'EOF'
jobs:
  sync:
    steps:
      - name: Only step
        run: echo
EOF
    cp wf.yml wf.before
    mkdir -p src/stubs
    cat >src/stubs/.clean <<'EOF'
KEY wf.yml ["jobs","sync","steps",{"name":"Missing"},"run"]
KEY wf.yml ["jobs","sync","steps",5,"run"]
KEY wf.yml ["jobs","other"]
EOF
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    cmp wf.yml wf.before
}

@test "configure-feature .clean KEY handles YAML holding multi-line block scalars" {
    # yq serialises a block scalar as a JSON string with an escaped \n, which
    # a shell echo (dash) would expand into a raw newline and break the JSON.
    require_mikefarah_yq
    cat >wf.yml <<'EOF'
jobs:
  sync:
    steps:
      - name: Report
        run: |
          echo one
          echo two
        if: old
EOF
    mkdir -p src/stubs
    cat >src/stubs/wf.yml <<'EOF'
jobs:
  sync:
    steps:
      - name: Report
        if: new
EOF
    echo 'KEY wf.yml ["jobs","sync","steps",{"name":"Report"},"if"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ "$(yq '.jobs.sync.steps[0].if' wf.yml)" = "new" ]
    [ "$(yq '.jobs.sync.steps[0].run' wf.yml)" = "$(printf 'echo one\necho two')" ]
}

@test "configure-feature .clean KEY skips files that are neither JSON nor YAML" {
    echo "line" >notes.txt
    cp notes.txt notes.before
    mkdir -p src/stubs
    echo 'KEY notes.txt ["a"]' >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    cmp notes.txt notes.before
    [[ "$output" == *"only JSON and YAML"* ]]
}

@test "configure-feature does not deploy .clean itself as a stub" {
    mkdir -p src/stubs
    echo "RMV foo.txt" >src/stubs/.clean
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ ! -f .clean ]
}

@test "configure-feature runs configure-*.sh scripts from source when at repo top level" {
    cat >src-configure.sh <<'EOF'
EOF
    mkdir -p src
    cat >"src/configure-thing.sh" <<EOF
#!/bin/sh
touch "$WORK_DIR/configure-ran.txt"
EOF
    chmod +x src/configure-thing.sh
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ -f "$WORK_DIR/configure-ran.txt" ]
}

@test "configure-feature skips configure-*.sh scripts when not at repo top level" {
    mkdir -p src sub
    cat >"src/configure-thing.sh" <<EOF
#!/bin/sh
touch "$WORK_DIR/configure-ran-sub.txt"
EOF
    chmod +x src/configure-thing.sh
    cd sub
    run configure-feature -s "$WORK_DIR/src" myfeature
    [ "$status" -eq 0 ]
    [ ! -f "$WORK_DIR/configure-ran-sub.txt" ]
    [[ "$output" == *"Not in top level directory"* ]]
}
