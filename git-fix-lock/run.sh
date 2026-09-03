#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Fix git lock files - resolve conflicts and regenerate lock files" $0 "$@" <<-help
help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# List files with conflicts and filter only lock files
conflicted_files=$(git diff --name-only --diff-filter=U | grep -E 'composer.lock|package-lock.json|yarn.lock')

# Process each lock file with conflicts
for file in $conflicted_files; do

    # Keep our version of the lock file, then regenerate it below
    zz_log i "Fixing merge conflict in $file"
    git checkout --ours "$file"

    # Regenerate the lock file based on the type of file
    case "$file" in
    composer.lock)
        # Regenerate composer.lock file with minimal changes
        zz_log i "Regenerating composer.lock..."
        composer update --lock --minimal-changes --ignore-platform-reqs --with-all-dependencies --no-scripts --no-interaction --no-progress --no-install
        ;;
    package-lock.json)
        # Check if the project uses npm workspaces and regenerate package-lock.json accordingly
        zz_log i "Regenerating package-lock.json..."
        ws=$(npm pkg get workspaces)
        if test "$ws" = "undefined" || test "$ws" = "{}"; then
            npm install --package-lock
        else
            npm install --package-lock --ws --if-present --include-workspace-root
        fi
        ;;
    yarn.lock)
        # Regenerate yarn.lock file
        zz_log i "Regenerating yarn.lock..."
        yarn install --check-files
        ;;
    esac
    # Stage the updated lock file for commit
    zz_log i "Staging $file for commit..."
    git add "$file"
done
