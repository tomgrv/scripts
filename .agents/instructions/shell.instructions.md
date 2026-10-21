---
applyTo: '**/run.sh'
description: 'Shell script conventions for the zz-* and functional scripts: block comments and file layout.'
---

<!-- @format -->

## Shell Scripts

### Comment every high-level block

Every high-level code block (an argument parse, a parameter check, a function, a `# --- section` of the main flow, a loop or branch that is a step of the script) gets a comment saying what it does and, when not obvious, why. One or two lines. Do not comment single statements.

### Layout

Order every `run.sh` the same way:

1. **Header** – usage comment, then `. zz-colors` (and `set -e` if used).
2. **Default `zz-args`** – the `eval "$(zz-args ... <<help ... help)"` block declaring every option and positional. No hand-written `getopts` or `case "$1"` loops.
3. **Parameters handling** – validate the parsed values, apply defaults, derive paths and names. Fail early with `zz-log e` and a usage line.
4. **Function definitions** – all helpers, each with a comment.
5. **Code blocks** – the main flow, one commented `# --- step` block at a time.

A script whose later arguments depend on earlier work (a second `zz-args` call after discovery) keeps the first three parts at the top and says why in a comment.

### Reuse before writing

Prompt with `zz-prompt` (confirmations: `zz-prompt -c Yn "Q?"`; secrets: `zz-prompt -s`, persisted with `zz-persist -s`), install with `zz-install`, pick a bin dir with `zz-bindir`, fetch repos with `zz-fetch`, choose with `zz-menu`.

### Logging

- Script messages go through `zz-log <level>`; the caller sets `ZZ_LOG_STEP` (current step) and raises `ZZ_LOG_INDENT` by 2 for a nested child.
- What a command prints (git, an installer) is operation output: forward it with `... | zz-log o` or `out=$(cmd 2>&1) || rc=$?`.

### POSIX `sh` only

Write `#!/bin/sh` scripts that run under dash and busybox. No bashisms:

- Tests: `[ ]` with `=`, never `[[ ]]`, `==` or `test` mixed with `[ ]`. Quote every expansion: `"$var"`.
- Arithmetic: `$((a + 1))`, never `expr`.
- Input: pipe or here-doc (`printf '%s\n' "$json" | jq …`), never `<<<`.
- No arrays, `${var//x/y}`, `$'…'`, `PIPESTATUS`, `source` or `function`. Use `sed`/`tr`, `.`, and a captured `$?` instead.
- `local` is allowed (dash and busybox support it); declare every function variable with it.

### Functions

- One job per function, named for what it answers: `is_*` returns a status, `get_*` prints one value.
- Document each parameter with a trailing comment, marking it mandatory or optional; default with `${1:-.}`.
- Take input on stdin when the function is a filter, so it composes in a pipe.
- stdout carries data only. All logging goes through `zz-log` (stderr).

### Flow

- Fail at the point of detection with a guard clause: `zz-log e "<the specific thing>" && exit 1`.
- Choose between variants with `case`, using `continue` to skip a missing one. Do not chain `if`/`elif` over the same key.
- Resolve a value from several sources as a flat cascade, one `if [ -n "$opt" ] && [ -z "$value" ]` step per source, in priority order, and log which source won.
- Cache expensive results by content hash, and only when the caller opts in.
