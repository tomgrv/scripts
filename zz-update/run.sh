#!/bin/sh
# zz-update — force a fresh download of the zz-* bundle, bypassing the
# local cache (ZZ_CACHE_DIR, default ~/.cache/zz_scripts), and re-link the
# core zz-* scripts from it. Equivalent to `zz-use --force <core zz-*>`.
#
# No-op (and a no-network fast path) when run from a local checkout of
# this repo: zz-use always installs the bundle straight from disk there,
# ignoring the cache entirely.

set -e

exec zz-use --force \
    zz-use zz-colors zz-log zz-args zz-prompt zz-ask zz-menu zz-input zz-bindir zz-dispatch zz-npx zz-persist zz-call zz-update
