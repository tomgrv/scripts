<!-- @format -->

# zz-fetch

Get a git repository into a directory: shallow clone when absent,
fast-forward to the ref when it is already a checkout, used as is when it
exists and is not a checkout. git comes from `zz-install` when missing.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-fetch`.

## Usage

```sh
zz-fetch [-r ref] -d <dir> <url>

zz-fetch -r v1.2.0 -d /opt/tool https://github.com/org/tool.git
```

`-r` defaults to `main`. What git prints is forwarded through `zz-log o`
(operation output), apart from the script's own log lines.

## Tests

```sh
bats test.bats
```
