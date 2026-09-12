# Changelog

## 0.13.0 (2026-09-12)

*Commits from: v0.12.0..HEAD*

### 📂 Unscoped changes

#### Bug Fixes

- 🐛 🔧 bump create-pr action pin to v2 (#23)
- 🔧 make zz_args pass-through eval-safe grant workflows perm to update-features (#25)

#### Other changes

- Merge tag 'v0.12.0' into develop

## 0.12.0 (2026-09-12)

*Commits from: v0.11.0..HEAD*

### 📂 Unscoped changes

#### Features

- ✨ add repo help MCP server via .mcp.json (#21)

#### Other changes

- Merge tag 'v0.11.0' into develop
- 📚️ update zz_persist's README table entry for -i/-v/-s (#19)
### 📦 devcontainer changes

#### Features

- add githooks and gitutils features (#5)

### 📦 zz_persist changes

#### Bug Fixes

- mask secret leak in interactive prompt (#20)

## 0.11.0 (2026-09-11)

*Commits from: v0.10.0..HEAD*

### 📂 Unscoped changes

#### Bug Fixes

- 🐛 route GITLEAKS_LICENSE through env in validate-pr-secret workflow (#17)

#### Other changes

- Merge tag 'v0.10.0' into develop
### 📦 zz_persist changes

#### Features

- add interactive -i/-v/-s prompting (#16)

## 0.10.0 (2026-09-08)

*Commits from: v0.9.0..HEAD*

### 📂 Unscoped changes

#### Bug Fixes

- 🐛 honor bump-version's -r/--range instead of overriding it (#15)

#### Other changes

- Merge tag 'v0.9.0' into develop
- 🔧 bump stale release-promote/scripts-ref pins (#14)

## 0.9.0 (2026-09-08)

*Commits from: v0.8.0..HEAD*

### 📂 Unscoped changes

#### Features

- ✨ add gv, bump-tag, bump-changelog, bump-version packages (#13)

#### Other changes

- Merge tag 'v0.8.0' into develop

## 0.8.0 (2026-09-08)

*Commits from: v0.7.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v0.7.0' into develop
### 📦 zz_log changes

#### Bug Fixes

- stop double-printing warnings/notices/errors in GitHub Actions (#12)

## 0.7.0 (2026-09-08)

*Commits from: v0.6.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v0.6.0' into develop
### 📦 devcontainer-features-ai-coding changes

#### Features

- ✨ 🔥 add .clean files for legacy stub cleanup (#10)

## 0.6.0 (2026-09-07)

*Commits from: v0.5.0..HEAD*

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v0.5.0' into develop

## 0.5.0 (2026-09-07)

*Commits from: v0.4.0..HEAD*

### 📂 Unscoped changes

#### Features

- ✨ zz_log emits ::warning::/::error:: annotations in GitHub Actions (#8)

#### Other changes

- Merge tag 'v0.4.0' into develop

## 0.4.0 (2026-09-06)

_Commits from: v0.3.0..HEAD_

### 📂 Unscoped changes

#### Other changes

- Merge tag 'v0.3.0' into develop
- add devcontainer configuration with features
- 🔧 update devcontainers
- 🚨 exhaustive behavioral coverage for all scripts (#4)

### 📦 load-json changes

#### Bug Fixes

- avoid dash echo mangling backslashes in downloaded JSON (#6)

### 📦 release-main changes

#### Other changes

- 🔧 pin scripts-ref to the released v0.3.0 tag

## 0.3.0 (2026-09-03)

_Commits from: 1f8f641ab8346b0a06735380ec9553077d56304f..HEAD_

### 📂 Unscoped changes

#### Other changes

- Merge branch 'release/0.1.0'
- Merge branch 'release/0.2.0'
- Merge tag 'v0.1.0' into develop
- Merge tag 'v0.2.0' into develop
- scaffold reusable shell script library (#1)
- zz_use's cache/download validity checks hardcoded zz_colors (#2)
- 🔧 allow git push/tag without prompting
- 🔧 bump version to 0.1.0
- 🔧 bump version to 0.2.0
- 🔧 deploy githooks devcontainer feature stubs

### 📦 git-release-beta changes

#### Other changes

- ✨ add gitutils scripts migrated from devcontainer-features (#3)

### 📦 gitutils changes

#### Other changes

- deploy gitutils devcontainer feature stubs

### 📦 release-main changes

#### Other changes

- 🔧 bootstrap-pin scripts-ref to the merge commit

### 📦 zz_use changes

#### Other changes

- install a script's config/ dir alongside it in the bin dir










---
*Generated on 2026-09-12 by [tomgrv/devcontainer-features](https://github.com/tomgrv/devcontainer-features)*
