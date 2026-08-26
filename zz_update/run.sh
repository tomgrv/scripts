#!/bin/sh
# zz_update — force a fresh download of the zz_* bundle, bypassing the
# local cache (ZZ_CACHE_DIR, default ~/.cache/zz_scripts), and re-link the
# core zz_* scripts from it. Equivalent to `zz_use --force <core zz_*>`.
#
# No-op (and a no-network fast path) when run from a local checkout of
# this repo: zz_use always installs the bundle straight from disk there,
# ignoring the cache entirely.

set -e

exec zz_use --force \
    zz_use zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist zz_wrap zz_update
