<!-- @format -->

# zz-interactive

Exit 0 when a script may ask the user something, 1 otherwise: the one test behind every menu and prompt (`zz-vars`, `zz-persist -i`, `zz-setup`, the `vps-access` menus).

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `zz-interactive`.

## Usage

```sh
if zz-interactive; then choice=$(zz-menu ...); fi
```

| Condition                                                  | Result |
| ---------------------------------------------------------- | ------ |
| `ZZ_INTERACTIVE=0` (or the older `SYSTEM_ACCESS_MENU=false`) | no     |
| stdin is a terminal                                         | yes    |
| stdin is a pipe (`curl \| sh`) but `/dev/tty` can be read   | yes    |
| otherwise, or `ZZ_PROMPT_TTY=0`                             | no     |

## Tests

```sh
bats test.bats
```
