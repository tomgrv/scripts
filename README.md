<!-- @format -->

# scripts

Small, self-contained shell tools (POSIX `sh`) you install on demand: git
helpers, JSON/YAML utilities, Kubernetes helpers and the `zz-*` building
blocks for writing your own scripts. Each tool lives in its own folder with a
README giving its usage.

**Start here**

- Install the core: [Quick start](#quick-start); get tools by name: [`zz-use`](#installing-tools-with-zz-use).
- Write a script with the blocks: [Writing your own script](#writing-your-own-script) and the [`zz-*` core](#core-zz-).
- Configure behaviour: [Environment variables](#environment-variables).
- Find a tool: [JSON, YAML, Kubernetes and feature tools](#json-yaml-kubernetes-and-feature-tools), [release](#release-and-versioning), [git](#git-tools).
- Add or change a tool: [Contributing](#contributing).

## Quick start

Install the `zz-*` core once (needs only `curl` and `sh`):

```sh
curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
```

Anything after the script is the tool to install and run, with its arguments
(`zz-use -x`); `ZZ_ORIGIN_REF` pins a ref. As root, let the shell read the
script (`sudo sh -c "$(curl ...)"`) rather than piping it into `sudo`, which
does not forward typed answers to the prompts:

```sh
sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh)" setup <tool> [args...]
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

| Script                                                                                                                 | Purpose                                                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `zz <name> [args...]`                                                                                                  | front door: runs `zz-<name>` if installed, else `zz-use -x <name>` (install on demand, then run)                                                                                               |
| `zz-use <tool>[@ref]`                                                                                                  | the activator: resolve/install a dependency, if and only if missing (see below)                                                                                                                |
| `zz-update`                                                                                                            | force a fresh download of the zz-\* bundle, bypassing the local cache                                                                                                                          |
| `zz-colors`                                                                                                            | ANSI color vars (`$Red` `$Green` ... `$End`); source it: `. zz-colors`                                                                                                                         |
| `zz-log <lvl> <msg...>`                                                                                                | colored, leveled log line on stderr (`i`/`w`/`e`/`s`/`-`)                                                                                                                                      |
| `zz-args <title> <caller> <<-help ...`                                                                                 | parse `$@` per a spec; `eval $(zz-args ...)` to bind the vars                                                                                                                                  |
| `zz-prompt [-s] [-e] [-k] [-c Yn] <question> [default]`                                                                | interactive free-form input (`-k`/`-c`: one keypress on a terminal); `ZZ_PROMPT_ANSWERS=<file>` scripts the answers                                                                            |
| `zz-menu [-t title] [-d key] [-f footer] [-c states] <key=label>...`                                                   | interactive numbered menu (pick or cycle; TAB-separated cells are aligned in columns)                                                                                                          |
| `zz-load [-r] [file\|url\|literal]`                                                                                    | read from a URL, a file, a literal arg or stdin                                                                                                                                                |
| `zz-bindir [-t target]`                                                                                                | resolve/create a writable bin dir; `eval $(zz-bindir ...)` to bind `$dir` and extend `PATH`                                                                                                    |
| `zz-dispatch <caller> <subcmd>`                                                                                        | dispatch an underscore-prefixed caller to a sibling `<name>-<subcmd>` script                                                                                                                   |
| `zz-npx [-s] <tool>`                                                                                                   | run a local `node_modules/.bin` binary, falling back to `npx`                                                                                                                                  |
| `zz-persist [-f file] [-p profile] [-s\|-S] [-i <question> [-v <default>]] [-g n [-t hex]] [-o\|-r\|-u] <key> [value]` | upsert a `KEY=VALUE` pair into an env file and/or a profile snippet; generate, print, show or remove a value; `-S` = secret in the shared secrets file                                         |
| `zz-call [-p package.json] [command...]`                                                                               | resolve a caller's declared env vars with `zz-vars`, then run a command with them or print `export` lines                                                                                      |
| `zz-install [-f] [-u url ...] <name> [<manager>=<name>...]`                                                            | install a system package via apt/apk/dnf/yum/brew/pacman/zypper/winget (per-manager name overrides; `-f` upgrades the system first), or with `-u` a downloaded binary into the `zz-bindir` dir |
| `zz-fetch [-r ref] -d <dir> <url>`                                                                                     | shallow clone or fast-forward a git repository into a directory                                                                                                                                |
| `zz-require [-n name] <root \| os=<id>>...`                                                                            | check what a step needs from its host (root, OS id); exit 1 naming the first unmet requirement                                                                                                 |
| `zz-vars [-S] [-n\|-a] [-m] [-e] -f <envfile> <name>=<dir>...`                                                         | show, ask and resolve the inputs workspaces declare (the menu marks saved values, shows where each comes from, deletes one); prints `export` lines                                             |
| `zz-setup <org>/<repo>[@<ref>] [args...]`                                                                              | clone/update a GitHub repo, propose its runnable workspaces, offer their declared inputs, then run them (else its setup entrypoint)                                                            |
| `zz-interactive`                                                                                                       | exit 0 when the caller may ask the user something (`ZZ_INTERACTIVE=0` turns it off)                                                                                                            |
| `zz-step`                                                                                                              | sourced `up\|down\|summary` entry point of a setup step: `. zz-step`                                                                                                                           |

## Environment variables

| Variable                                                                                                                     | Used by                                | Meaning                                                                                               |
| ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `ZZ_ORIGIN`, `ZZ_ORIGIN_REF`                                                                                                 | `zz-use`, `setup.sh`                   | repository and ref tools are downloaded from (default `tomgrv/scripts`, `main`)                       |
| `ZZ_CACHE_DIR`, `ZZ_CACHE_TTL`                                                                                               | `zz-use`                               | download cache (`~/.cache/zz_scripts`) and its lifetime in minutes (default 1440, `0` = always fetch) |
| `ZZ_USE_CONFIG`, `ZZ_USE_REPO_URL`                                                                                           | `zz-use`                               | external-tool catalogue and repository URL overrides                                                  |
| `ZZ_BIN_DIR`                                                                                                                 | `zz-bindir`                            | force the directory tools are linked into                                                             |
| `ZZ_DEBUG`, `ZZ_LOG_INDENT`                                                                                                  | `zz-log`                               | debug lines; indentation of nested output                                                             |
| `ZZ_INTERACTIVE`                                                                                                             | `zz-interactive` and every menu/prompt | `0` never asks (unattended); otherwise a terminal is used when there is one                           |
| `ZZ_PROMPT_TTY`                                                                                                              | `zz-prompt`                            | `0` forbids reading `/dev/tty` when stdin is not a terminal                                           |
| `NO_COLOR`                                                                                                                   | `zz-colors` (so every script)          | any non-empty value turns every colour code off (https://no-color.org)                                |
| `ZZ_PROMPT_MARK`, `ZZ_PROMPT_HINT`                                                                                           | `zz-prompt`, `zz-menu`                 | prompt line grammar: leading mark (default `#`), printf format of the hint (default `[%s]`, empty = none) |
| `ZZ_PROMPT_ANSWERS`                                                                                                          | `zz-prompt`, `zz-menu`                 | file of scripted answers, one line per prompt (tests, unattended demos)                               |
| `ZZ_SECRETS_FILE`                                                                                                            | `zz-persist -S`                        | the shared owner-only secrets file (default `/root/.zz-secrets.env`)                                  |
| `ZZ_PROFILE_DIR`                                                                                                             | `zz-persist`, `zz-vars`                | where profile snippets are written (default `/etc/profile.d`)                                         |
| `ZZ_SETUP_DIR`, `ZZ_SETUP_REF`, `ZZ_SETUP_URL_BASE`, `ZZ_SETUP_ENTRY`, `ZZ_SETUP_ENV_FILE`, `ZZ_SETUP_PROFILE`, `ZZ_ETC_DIR` | `zz-setup`                             | checkout location, ref, git host, entrypoint, state file, profile and `/etc` directory                |
| `ZZ_SETUP_ROOT`, `ZZ_SETUP_UP`                                                                                               | set by `zz-setup` for its steps        | the checkout, and the workspaces this run brings up                                                   |

## JSON, YAML, Kubernetes and feature tools

| Script              | Purpose                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| `json`              | dispatch to `json-<subcommand>` (`load`, `validate`, `normalize`, `merge`) |
| `json-load`         | load JSON from a file/URL, tag it with `$id`                               |
| `json-validate`     | validate JSON against a (local/inferred/remote) JSON Schema                |
| `json-normalize`    | sort JSON keys per schema + alphabetically, optional in-place write        |
| `json-merge`        | recursively merge one JSON file into another (arrays deduped, unioned)     |
| `json-render`       | fill the `${NAME}` placeholders of a JSON file, values JSON-escaped        |
| `yaml`              | dispatch to `yaml-<subcommand>` (`merge`, `render`)                        |
| `yaml-merge`        | recursively merge one YAML file into another (arrays deduped, unioned)     |
| `yaml-render`       | fill the `${NAME}` placeholders of a YAML file (chart values, manifest)    |
| `kube`              | dispatch to `kube-<subcommand>` (`apply`, `rollout`, `require`, ...)       |
| `kube-progress`     | run a command, logging the pod status of a namespace while it works        |
| `kube-diagnose`     | show what is stuck in a Kubernetes namespace                               |
| `kube-teardown`     | uninstall a Helm release and delete its namespace                          |
| `kube-service-port` | change the port of a Service's named port                                  |
| `kube-require`      | check kubectl and helm, print the KUBECONFIG export for `eval`             |
| `kube-rollout`      | wait for a Deployment rollout with progress and diagnostics                |
| `kube-apply`        | render a manifest template (`yaml-render`) and `kubectl apply` it          |
| `systemd-service`   | enable or disable systemd units and check they run                         |
| `helm-repo`         | add and refresh Helm repositories, failing with a clear message            |
| `helm-install`      | install or upgrade a Helm release with progress and diagnostics            |
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

## Release and versioning

| Script           | Purpose                                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `bump-changelog` | generate a `CHANGELOG.md` entry from conventional commits, optionally bump files and tag |
| `bump-version`   | update version numbers in files (root and/or per-workspace)                              |
| `bump-tag`       | create or move a version tag (and its dependent major/minor tags), then push it          |
| `gv`             | call GitVersion with this repository's `.gitversion` configuration                       |

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

Each tool is a folder with `run.sh`, `package.json` (the `bin` entry, a
description and `peerDependencies` for the tools it calls), `README.md` and
`test.bats`.

```sh
npm test                          # every suite
bats json-validate/test.bats      # one suite (bats-core, bats-assert/file/detik)
```

Adding a tool:

1. Create the folder; start `run.sh` with `#!/bin/sh`, `. zz-colors`, then parse
   arguments with `zz-args` and log with `zz-log`. Keep it POSIX `sh`.
2. Call other tools by name and list them in `peerDependencies` (and in a
   `zz-use` line when a step installs them on a host).
3. Write `test.bats` with `load ../tests/helpers.bash` (`setup_scripts_path`
   puts every `run.sh` on `PATH`; `stub_script <name>` replaces one with a stub).
   Menus and prompts are scripted with `ZZ_PROMPT_ANSWERS=<file>`; a pty-only
   behaviour can run under `script -qec`.
4. Add the folder to the root `package.json` workspaces and a row to the table
   above; write the README (purpose, usage, options, exit status, tests).

Pull requests target `develop`. Version bumps and renames:
[`UPGRADING.md`](UPGRADING.md).
