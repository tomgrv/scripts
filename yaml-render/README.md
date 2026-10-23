<!-- @format -->

# yaml-render

Fill the `${NAME}` placeholders of a YAML file (Helm values, a Kubernetes manifest) and
print the result, so chart values live in a `.yaml` file instead of a heredoc.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `yaml-render`.

## Usage

```sh
yaml-render <file> [NAME[=value]]...

yaml-render values.yaml host=app.example.com port=8080 | kubectl apply -f -
yaml-render values.yaml host port     # values taken from the environment
```

Only the listed names are replaced; any other `${...}` in the file is left
as is. A value may hold `/`, `&`, `|` or `\`, but not a newline. A name that is
not `[A-Za-z_][A-Za-z0-9_]*` is refused. Quote a placeholder in the YAML
(`'${port}'`) to keep a numeric-looking value a string.

## Dependencies

Declared via `zz-use` at the top of `run.sh` and resolved on demand
(installed if and only if missing) — see `run.sh` for the exact list.

## Tests

```sh
bats test.bats
```

- help/usage output and exit code
- errors with no arguments or a missing file
- fills `NAME=value` pairs and variables from the environment
- leaves unlisted `${...}` text untouched
- keeps `/`, `&`, `|` and `\` in a value literal
- refuses an invalid name or a multi-line value
