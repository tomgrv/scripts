#!/bin/sh

eval $(
	zz-args "Fix git lock files - resolve conflicts and regenerate lock files" $0 "$@" <<-help
help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

conflicted_files=$(git diff --name-only --diff-filter=U | grep -E 'composer.lock|package-lock.json|yarn.lock')

for file in $conflicted_files; do

    # Keep our version, then regenerate below instead of trying to merge the lock file's conflict markers
    zz-log i "Fixing merge conflict in $file"
    git checkout --ours "$file"

    case "$file" in
    composer.lock)
        zz-log i "Regenerating composer.lock..."
        composer update --lock --minimal-changes --ignore-platform-reqs --with-all-dependencies --no-scripts --no-interaction --no-progress --no-install
        ;;
    package-lock.json)
        # npm workspaces need the extra flags, or the workspace root gets dropped
        zz-log i "Regenerating package-lock.json..."
        ws=$(npm pkg get workspaces)
        if test "$ws" = "undefined" || test "$ws" = "{}"; then
            npm install --package-lock
        else
            npm install --package-lock --ws --if-present --include-workspace-root
        fi
        ;;
    yarn.lock)
        zz-log i "Regenerating yarn.lock..."
        yarn install --check-files
        ;;
    esac
    zz-log i "Staging $file for commit..."
    git add "$file"
done
