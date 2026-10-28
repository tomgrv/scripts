<!-- @format -->

# zz-progress

A transient progress line for the slow part before a menu (reading files,
running `jq`...): it replaces the current line on stderr, then is cleared.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-progress`.

## Usage

```sh
zz-progress "Reading the inputs..."   # show the message
# ... slow work ...
zz-progress                           # clear it
```

Nothing is written when stderr is not a terminal, so scripts call it
unconditionally. There is no argument parsing, so a call costs next to
nothing. A menu draws below the cleared line.

## Tests

```sh
bats test.bats
```

- shows the message on a terminal and clears it with no argument
- writes nothing when stderr is not a terminal
