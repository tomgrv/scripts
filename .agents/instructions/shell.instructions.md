---
applyTo: '**/run.sh'
description: 'POSIX sh conventions for the zz-* and functional scripts: file layout, comments, functions, flow, indentation and naming.'
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

### Indentation and spacing

- Indent with 4 spaces, never tabs. This is the repo's prettier setting (`tabWidth: 4`, `useTabs: false`, `singleQuote`); run `npx prettier --write` on edited scripts and keep what it produces.
- In a `case`, align each pattern with `case` and indent its body one level. End a branch with `;;` at the body's indent.
- Keep a one-line body on one line when it stays short: `is_json() { jq empty 2>/dev/null; }`. Open a block as soon as it holds a second statement.
- Leave one blank line between functions, between `# --- step` blocks, and around each top-level `if`, `for`, `while` or `case`. Never leave two in a row.
- Group a function's `local` lines together and follow them with one blank line. Do not open a short function with a blank line.
- Inside a `case`, leave one blank line after `case … in` and after each pattern line when the body has more than one statement.
- Keep an option's help text in the `zz-args` here-doc aligned in columns: short flag, long name, variable, description.
- Wrap a pipeline at `|` only past 100 characters, and indent the continuation one level.

### Naming

- Script folders are `kebab-case`, `<domain>-<action>` (`json-validate`, `git-fix-up`). Shared helpers take the `zz-` prefix. The entry point is always `run.sh`.
- Functions are `snake_case`, verb first: `is_*` and `has_*` answer yes or no, `get_*` prints a value, other verbs act (`install_package`). A helper that is not the script's purpose may take a leading `_` (`_collect`).
- A function that mirrors a name from the domain keeps that name's case: `oneOf_rule` matches the JSON Schema keyword `oneOf`.
- Variables are lowercase and short, named for what they hold: a singular noun for one value (`json`, `schema`, `path`), a plural for a list (`props`, `items`). Say what a flag means, not how it is stored: `allow`, not `flag1`.
- An option's long name equals its variable (`-s schema` fills `$schema`). Its short flag is the first letter, or the next free one.
- Colour variables from `zz-colors` are Capitalised (`Yellow`, `None`). Environment variables are `UPPER_SNAKE` with the `ZZ_` prefix (`ZZ_LOG_STEP`).
- Avoid abbreviations unless they are standard (`dir`, `tmp`, `url`). Do not introduce a second name for something that already has one in the script.
