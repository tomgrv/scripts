<!-- @format -->

# zz-require

Check what a step needs from its host before it changes anything.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-require`. Used by `zz-setup`.

## Usage

```sh
zz-require [-n name] <requirement>...

zz-require -n vps-rancher root os=ubuntu
```

A requirement is `root` (running as root) or `os=<id>` (the `ID` of
`/etc/os-release`, e.g. `os=ubuntu`). Exits 1, saying which one is missing, on the
first that is not met. `-n` names the step in the messages. A workspace declares
them in its `package.json` as `config.requires`, e.g. `{"root": true, "os": "ubuntu"}`.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- errors for an unknown requirement
- `root` passes as root and fails otherwise, naming the step
- `os=<id>` passes on a matching `/etc/os-release` ID and fails on another
