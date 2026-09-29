#!/bin/bash

# Reapply file mode changes (chmod) from the working tree diff without touching content

cd "$(git rev-parse --show-toplevel)" >/dev/null || exit 0

# Restore the mode recorded in the index straight from `git diff --raw`, instead of replaying a
# reverse patch through `git apply`, which warns ("has type X, expected Y") whenever a file's
# on-disk mode no longer matches the patch. Deleted files have no mode to restore and are skipped.
git diff --raw -z --no-renames --diff-filter=M | while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    # shellcheck disable=SC2086
    set -- $meta
    old=${1#:}
    new=$2
    [ "$old" != "$new" ] || continue
    case "$old" in
    100755) chmod 755 -- "$path" ;;
    100644) chmod 644 -- "$path" ;;
    esac
done

exit 0
