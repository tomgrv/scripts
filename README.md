<!-- @format -->

# scripts

Small, self-contained shell tools (POSIX `sh`) you install on demand: git
helpers, JSON/YAML utilities, Kubernetes helpers and the `zz-*` building
blocks for writing your own scripts. Each tool lives in its own folder with a
README giving its usage.

## Quick start

Install the `zz-*` core once (needs only `curl` and `sh`):

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
```

Then get any tool by name, or run it straight away:

```sh
zz-use git-fix-up json-validate     # install what is missing, skip what is there
zz json-validate my.json            # install on demand, then run
zz-use -x git-release-prod          # install, then exec
```

Git tools are installed as `git-<name>` and run as `git <name>`
(`git-fix-up` → `git fix-up`). Refresh everything with `zz-update`.

## Installing tools with `zz-use`

`zz-use <tool>...` installs each tool only if it is not already on your `PATH`.
A tool is a script from this repository, or an external program (installed with
your system package manager, or from a download declared in
[`zz-use/config/zz-use.json`](zz-use/config/zz-use.json)).

| You want                 | Run                                        |
| ------------------------ | ------------------------------------------ |
| Several tools            | `zz-use zz-log zz-args jq`                 |
| A whole family           | `zz-use "git-fix-*"`                       |
| A pinned version         | `zz-use json-validate@v2`                  |
| A tool from another repo | `zz-use someorg/otherscripts/some-tool@v1` |
| Install, then run        | `zz-use -x json-validate some-file.json`   |
| Force a fresh download   | `zz-update` or `zz-use --force <tool>`     |

Downloads are cached in `~/.cache/zz_scripts` (`ZZ_CACHE_DIR`). Use another
fork or ref with `ZZ_ORIGIN` (default `tomgrv/scripts`) and `ZZ_ORIGIN_REF`
(default `main`).

## Writing your own script

Start a script by declaring what it needs, then parse its arguments:

```sh
#!/bin/sh
zz-use zz-colors zz-args jq

eval $(zz-args "Say hello" $0 "$@" <<help
    n name    name    who to greet
help
)

zz-log i "Hello $name"
```

Folders are self-contained, so any tool can also be copied out and used on its
own, or installed from npm: `npm install --save-dev ./json-validate`.

## Core: `zz-*`

| Script                                                                                | Purpose                                                                                                                                                        |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `zz <name> [args...]`                                                                 | front door: runs `zz-<name>` if installed, else `zz-use -x <name>` (install on demand, then run)                                                               |
| `zz-use <tool>[@ref]`                                                                 | the activator: resolve/install a dependency, if and only if missing (see below)                                                                                |
| `zz-update`                                                                           | force a fresh download of the zz-\* bundle, bypassing the local cache                                                                                          |
| `zz-colors`                                                                           | ANSI color vars (`$Red` `$Green` ... `$End`); source it: `. zz-colors`                                                                                         |
| `zz-log <lvl> <msg...>`                                                               | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)                                                                                                      |
| `zz-args <title> <caller> <<-help ...`                                                | parse `$@` per a spec; `eval $(zz-args ...)` to bind the vars                                                                                                  |
| `zz-prompt <question> [default]`                                                      | interactive free-form input                                                                                                                                    |
| `zz-menu [-t title] [-d key] [-f footer] [-c states] <key=label>...`                  | interactive numbered menu; prints the chosen key (or, with `-c`, each item's cycled `key=state`)                                                               |
| `zz-load [file]`                                                                      | read from arg (literal or file) or stdin                                                                                                                       |
| `zz-bindir [-t target]`                                                               | resolve/create a writable bin dir; `eval $(zz-bindir ...)` to bind `$dir` and extend `PATH`                                                                    |
| `zz-dispatch <caller> <subcmd>`                                                       | dispatch an underscore-prefixed caller to a sibling `<name>-<subcmd>` script                                                                                   |
| `zz-npx [-s] <tool>`                                                                  | run a local `node_modules/.bin` binary, falling back to `npx`                                                                                                  |
| `zz-persist [-f file] [-p profile] [-s] [-i <question> [-v <default>]] <key> [value]` | upsert a `KEY=VALUE` pair into an env file and/or `/etc/profile.d`; `-i` asks for the value, `-s` marks it secret (masked, owner-only targets only)            |
| `zz-call [-p package.json] [command...]`                                              | resolve a caller's declared env vars (`config.input`/`config.output` in `package.json`; ask + persist if missing), then run a command                          |
| `zz-install [-u url ...] <name> [<manager>=<name>...]`                                | install a system package via apt/apk/dnf/yum/brew/pacman/zypper/winget (per-manager name overrides), or with `-u` a downloaded binary into the `zz-bindir` dir |
| `zz-fetch [-r ref] -d <dir> <url>`                                                    | shallow clone or fast-forward a git repository into a directory                                                                                                |
| `zz-require [-n name] <root \| os=<id>>...`                                           | check what a step needs from its host (root, OS id); exit 1 naming the first unmet requirement                                                                 |
| `zz-vars [-S] -f <envfile> <name>=<dir>...`                                           | show, ask and resolve the inputs workspaces declare; prints `export` lines                                                                                     |
| `zz-setup <org>/<repo>[@<ref>] [args...]`                                             | clone/update a GitHub repo, propose its runnable workspaces, offer their declared inputs, then run them (else its setup entrypoint)                            |

## JSON, YAML, Kubernetes and feature tools

| Script              | Purpose                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| `json`              | dispatch to `json-<subcommand>` (`load`, `validate`, `normalize`, `merge`) |
| `json-load`         | load JSON from a file/URL, tag it with `$id`                               |
| `json-validate`     | validate JSON against a (local/inferred/remote) JSON Schema                |
| `json-normalize`    | sort JSON keys per schema + alphabetically, optional in-place write        |
| `json-merge`        | recursively merge one JSON file into another (arrays deduped, unioned)     |
| `json-render`       | fill the `${NAME}` placeholders of a JSON file, values JSON-escaped        |
| `yaml-render`       | fill the `${NAME}` placeholders of a YAML file (chart values, manifest)    |
| `kube-progress`     | run a command, logging the pod status of a namespace while it works        |
| `kube-diagnose`     | show what is stuck in a Kubernetes namespace                               |
| `kube-teardown`     | uninstall a Helm release and delete its namespace                          |
| `kube-service-port` | change the port of a Service's named port                                  |
| `feature`           | dispatch to `feature-<subcommand>` (`install`, `configure`, `context`)     |
| `feature-context`   | resolve a feature's source/target dirs from the calling script             |
| `edit-script`       | copy an installed script locally and open it for editing                   |
| `distribute-utils`  | copy `zz-*`/utility scripts into a project's local scripts directory       |
| `feature-install`   | copy a feature's stubs/config/bin into a target, run `install-*.sh`        |
| `feature-configure` | deploy a feature's stubs into the cwd (merging), run `configure-*.sh`      |

## Workspaces

| Script        | Purpose                                                                                      |
| ------------- | -------------------------------------------------------------------------------------------- |
| `ws-list`     | list workspace directories, filter (`-b`, `-e`), order (`-o`) or restrict to affected (`-r`) |
| `ws-impacted` | print the `list-packages` filter for the workspaces impacted by changed files                |
| `ws-test`     | run a workspace's `.scripts.test` entry as its test suite                                    |

## Git tools

| Script                      | Purpose                                                                  |
| --------------------------- | ------------------------------------------------------------------------ |
| `git-align`                 | align the current branch with its remote counterpart                     |
| `git-autorebase`            | non-interactive rebasing with conflict resolution                        |
| `git-co`                    | enhanced commit                                                          |
| `git-degit`                 | clone and degit a repository                                             |
| `git-fix`                   | dispatch to `git-fix-<subcommand>`                                       |
| `git-fix-author`            | set `user.name`/`user.email` to a specified commit's author              |
| `git-fix-base`              | rebase commits from one branch onto another                              |
| `git-fix-blanks`            | discard whitespace/blank/quote-slash-only changes                        |
| `git-fix-children`          | delete all descendant tags and branches of a commit                      |
| `git-fix-date`              | fix commit dates/times in history                                        |
| `git-fix-del`               | delete a specified commit and rebase subsequent history                  |
| `git-fix-emoji`             | fix git emoji                                                            |
| `git-fix-last`              | edit the last commit's message and content                               |
| `git-fix-lock`              | resolve conflicts and regenerate lock files                              |
| `git-fix-message`           | rewrite an arbitrary commit message                                      |
| `git-fix-mode`              | fix file mode changes from diff                                          |
| `git-fix-orphans`           | prefix non-gitflow remote branches without a PR as `orphan/`             |
| `git-fix-privacy`           | fix privacy in history                                                   |
| `git-fix-prune`             | prune stale remote-tracking references                                   |
| `git-fix-rights`            | set appropriate file/directory permissions                               |
| `git-fix-secrets`           | redact a secret across git history                                       |
| `git-fix-up`                | amend a commit with current changes and rebase                           |
| `git-forall`                | execute a command for all files in the repository                        |
| `git-hook-commitmsg`        | `commit-msg` hook: apply commitlint + devmoji to the commit message      |
| `git-hook-installplugins`   | install npm plugins declared at a package.json key                       |
| `git-hook-postcheckout`     | `post-checkout` hook                                                     |
| `git-hook-postmerge`        | `post-merge` hook: keep merged lockfiles, prompt to reinstall            |
| `git-hook-precommit`        | `pre-commit` hook: sync lockfiles, run pre-commit checks and lint-staged |
| `git-hook-preparecommitmsg` | `prepare-commit-msg` hook: launch the commitizen prompt                  |
| `git-hook-prepush`          | `pre-push` hook: validate the current branch name                        |
| `git-getcommit`             | list history and ask for a commit to fix up                              |
| `git-integrate`             | integrate modifications from the remote repository                       |
| `git-pick`                  | pick files from a specific commit                                        |
| `git-release`               | dispatch to `git-release-<subcommand>`                                   |
| `git-release-alpha`         | squash-merge the current feature branch into develop                     |
| `git-release-beta`          | start a release branch via Git Flow                                      |
| `git-release-hotfix`        | start a hotfix branch via Git Flow                                       |
| `git-release-prod`          | finish a release/hotfix branch via Git Flow                              |
| `git-unset`                 | unset all git config keys starting with a given prefix                   |
| `php-list-changed`          | list PHP test parts (core/modules/packages) affected by a change         |

## Contributing

Each tool is a folder with `run.sh`, `package.json`, `README.md` and
`test.bats`. Run all tests with `npm test`, or one with
`bats json-validate/test.bats`. Pull requests target `develop`. Version bumps
and renames: [`UPGRADING.md`](UPGRADING.md).
