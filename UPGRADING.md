<!-- @format -->

# Upgrading

How to ship, and consume, a **breaking rename** of scripts without breaking
CI, releases or downstream repos. Written from the v1.0.0 rename
(`zz_*` → `zz-*`, `<verb>-json|yaml` → `json-<verb>|yaml-<verb>`, new `json` and
`yaml` dispatchers). Sibling guides: `tomgrv/actions`,
`tomgrv/devcontainer-features`, `perspikapps/vps` (`UPGRADING.md` in each).

## Version map for the rename

| Repo                           | Before | After  |
| ------------------------------ | ------ | ------ |
| `tomgrv/scripts`               | v0.34  | v1.0.0 |
| `tomgrv/actions`               | v2.46  | v3.0.0 |
| `tomgrv/devcontainer-features` | v8.29  | v9.0.0 |
| `perspikapps/vps`              | v0.3   | v1.0.0 |

A breaking change must promote the **major** in every repo. Floating tags
(`v1`, `v3`, …) only move forward within a major, so `@v2` / `scripts-ref: v0`
keep resolving to the old code forever.

## Renames at a glance

| Old                                                                         | New                                                                         |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `zz_args zz_ask zz_bindir zz_call zz_colors zz_dispatch zz_input`           | `zz-args zz-ask zz-bindir zz-call zz-colors zz-dispatch zz-input`           |
| `zz_install zz_log zz_menu zz_npx zz_persist zz_prompt zz_update zz_use`    | `zz-install zz-log zz-menu zz-npx zz-persist zz-prompt zz-update zz-use`    |
| glob `zz_*`, config `config/zz_use.json`                                    | glob `zz-*`, `config/zz-use.json`                                           |
| `normalize-json merge-json validate-json load-json`                         | `json-normalize json-merge json-validate json-load` (+ `json <sub>`)        |
| `merge-yaml`                                                                | `yaml-merge` (+ `yaml <sub>`)                                               |
| npm `@tomgrv/scripts-zz_args` …                                             | `@tomgrv/scripts-zz-args` …                                                 |
| shims `zz_context zz_dist zz_edit zz_json`                                  | `zz-context zz-dist zz-edit zz-json`                                        |

**Deliberately unchanged** (data, not scripts): `.zz_dist`, `config.zz_dist`,
`~/.cache/zz_scripts`, the `.zz_use` marker dir, `ZZ_*` environment variables.

## Order of operations (the dependency chain)

CI everywhere installs `tomgrv/scripts` **`main`** and runs the **published**
`tomgrv/actions@<major>`. So a rename deadlocks unless you go in this order:

1. **scripts** — rename, merge to `develop`, run `release-prod` → `main` and
   the new major tag exist. Other repos' CI can now fetch the new names.
2. **actions** — merge (CI is red here and only here: it runs the old published
   `@v2`, whose `setup-scripts` calls `zz_use`; this needs an explicit decision to
   merge red). Its `release-prod.yml` must bootstrap from the checked-out code
   (`uses: ./release-promote`), because the published previous major still calls
   the old names. `release-prod` → new major tag.
3. **devcontainer-features**, **vps** — pin `tomgrv/actions@<new major>`, merge
   when green, release.
4. **Follow-up pins** — bump any remaining `@v<old>` / `scripts-ref: v<old>`
   references (including `scripts` and `actions` themselves), merge, patch
   release.

Always **dry-run first** (`workflow_dispatch` with `dry_run: true`), then the
real run. A dry run is what exposed the pinned-old-`release-promote` failure.

## Checklist for the renaming repo (scripts)

1. `git mv` each script folder; update `package.json` `name`, `bin`,
   `peerDependencies`, and the root `workspaces` list.
2. Rewrite references with a **word-bounded** pattern (see Pitfalls) across all
   tracked regular files; skip `CHANGELOG.md`, `package-lock.json`, symlinks,
   `docs/reviews/`.
3. Add dispatchers (`json`, `yaml`): `run.sh` is `zz-dispatch $0 "$@"`; install
   them with their family glob (`zz-use json "json-*" yaml "yaml-*"`).
4. Update `setup.sh`, `zz-use` (glob `zz-*`, prefix tests such as `${tool#zz-}`),
   `distribute-utils` (`*zz-*`, `^_zz-`), docs and tests.
5. **Merge `develop` again before finishing**: scripts added meanwhile
   (e.g. `git-fix-orphans`) still use the old names and break the merge tree's
   `npm install` with a 404 on `@tomgrv/scripts-zz_args`.
6. Run the suite with a fresh cache: `ZZ_CACHE_DIR=$(mktemp -d) bats */test.bats`.
   `yaml-merge` tests need mikefarah/yq; failures that also occur on the base
   commit are environmental.
7. PR title scope must be `scripts-<folder>` and the header ≤ 100 chars.
   Squash-merge (merge commits are disabled) with `!` in the title **and** a
   `BREAKING CHANGE:` footer so the release tooling bumps the major.
8. `release-prod` dry run, then real. Verify the new `v<major>` tags.

## Pitfalls we hit

- **POSIX `sh` function names cannot contain `-`.** A stub that defined
  `zz-log() { … }` broke under `sh`. Make such stubs executables on `PATH`.
- **Quoted names are easy to miss** (`"$TEST_BIN/zz_dist"`): grep after rewriting.
- **Escaped Markdown** (`zz\_\*`) is not matched by a plain pattern.
- **`sed -i` on a symlink replaces it with a file.** Rewrite regular files only.
- **Stale local cache** (`~/.cache/zz_scripts`) makes a correct install look
  broken: use a fresh `ZZ_CACHE_DIR`.
- **Pinning an old `release-promote` does not help**: its `setup-scripts` step
  bootstraps `tomgrv/scripts` `main` regardless of `scripts-ref`.
- **Re-running a failed check reuses the old event payload** (old PR title): push
  a commit or mark the PR ready for review instead.
- **Ready-for-review starts extra checks** (title, source/target branch, lock)
  that never ran while the PR was a draft.
- **After a squash merge the remote branch may remain** (non-fast-forward on
  reuse): confirm its tree equals `develop`, then `--force-with-lease`.

## Upgrading a downstream repo

```sh
# 1. names
grep -rIl -E 'zz_(args|ask|bindir|call|colors|dispatch|input|install|log|menu|npx|persist|prompt|update|use)\b|(normalize|merge|validate|load)-json|merge-yaml' . \
  --exclude-dir=node_modules --exclude-dir=.git
# 2. pins
grep -rn -E 'tomgrv/actions[^ ]*@v2|scripts-ref: v0' .github
```

Replace per the table above, move `@v2` → `@v3` and `scripts-ref: v0` → `v1`,
rerun your installer (`configure-feature`, `zz-update`), then run your tests.

## Rollback

Pin the previous majors (`tomgrv/actions@v2`, `scripts-ref: v0`) **together**:
mixing a new `scripts` with an old `actions` fails at `zz_use: not found`.
