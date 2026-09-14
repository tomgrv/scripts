# run-workspace-tests

Run a workspace's `.scripts.test` entry (from each root `*.json` file) as its
test suite.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `run-workspace-tests`.

## Usage

```sh
run-workspace-tests <workspace>
```

For every root-level `*.json` file directly under `<workspace>` (not
recursive — typically `package.json`), reads its `.scripts.test` field and
runs it from within `<workspace>`:

- **No `*.json` file in the workspace** → silent skip, exits `0`.
- **`*.json` present but no `.scripts.test` entry** → warns and continues
  (exits `0` unless another file in the workspace fails).
- **`.scripts.test` present** → runs it, capturing combined output.
  - non-zero exit → propagated as a failure.
  - zero exit but no output at all → treated as a failure (a silently-empty
    test run, e.g. a test runner matching zero files, is a false green).

## Dependencies

Declared via `zz_use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- silent skip when the workspace has no root `*.json` file
- warns and continues when `.scripts.test` is absent
- propagates a non-zero exit from the test script
- errors when the test script produces no output
- passes through output and succeeds on the happy path
