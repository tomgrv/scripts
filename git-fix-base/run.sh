#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Fix git base - rebase commits from one branch to another" $0 "$@" <<-help
		    p -      push      push changes to remote
		    n -      dry-run   show what would be done without making changes
		    - target target    target branch to rebase commits onto
		    - source source    source branch to take commits from (default: current branch)
help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Validate required arguments
if [ -z "$target" ]; then
	zz_log e 'Target branch is required. Use -h for help.'
	exit 1
elif ! git rev-parse --verify "$target" >/dev/null 2>&1; then
	zz_log e "Target branch '$target' does not exist"
	exit 1
fi

# Get current branch if source is not specified and validate source branch exists
if [ -z "$source" ]; then
	source=$(git rev-parse --abbrev-ref HEAD)
	zz_log i "Using current branch as source: $source"
elif ! git rev-parse --verify "$source" >/dev/null 2>&1; then
	zz_log e "Source branch '$source' does not exist"
	exit 1
fi

# Validate that source and target are different
if [ "$source" = "$target" ]; then
	zz_log e "Source and target branches cannot be the same: $source"
	exit 1
fi

# Check if there are uncommitted changes
if git isDirty; then
	zz_log e 'Working directory is not clean. Please commit or stash your changes.'
	exit 1
fi

# Find the merge base between source and target
base=$(git merge-base "$source" "$target")
if [ -z "$base" ]; then
	zz_log e "Could not find common ancestor between '$source' and '$target'"
	exit 1
else
	zz_log i "Found merge base: $base"
fi

# Get commits that are not pushed on the source branch 
commits=$(git log --reverse --format=%H "$source" --not origin/"$source" --not "$target" --no-merges)	

if [ -z "$commits" ]; then
	zz_log i "No commits to move from '$source' to '$target'"
	exit 0
fi

# Count commits
count=$(echo "$commits" | wc -l)
zz_log i "Found $count commit(s) to move from '$source' to '$target'"

# Show commits in dry-run mode
if [ -n "$dryrun" ]; then
	zz_log i "Commits that would be moved:"
	echo "$commits" | while read commit; do
		if [ -n "$commit" ]; then
			echo "  $(git log --oneline -1 "$commit")"
		fi
	done
	zz_log i "To execute, run without -n flag"
	exit 0
fi

# Confirm the operation
zz_log i "About to move $count commit(s) from '$source' to '$target':"
echo "$commits" | while read commit; do
	if [ -n "$commit" ]; then
		zz_log - "  $(git log --oneline -1 "$commit")" >&2
	fi
done
zz_log i "This will:"
zz_log - " 1. Checkout '$target' branch"
zz_log - " 2. Create a temporary branch for the rebase"
zz_log - " 3. Cherry-pick commits from '$source'"
zz_log - " 4. Reset '$source' to the merge base"
zz_log - " 5. Fast-forward '$target' to include the rebased commits"
echo ""
if ! zz_ask "Yn" "Continue?"; then
	zz_log e "Operation cancelled"
	exit 1
fi

# Store current branch
current=$(git rev-parse --abbrev-ref HEAD)

# Create a temporary branch name
temp="temp-fix-base-$(date +%s)"

# Checkout target branch
zz_log i "Checking out '$target' branch"
if ! git checkout "$target"; then
	zz_log e "Failed to checkout '$target' branch"
	exit 1
fi

# Create temporary branch from target
zz_log i "Creating temporary branch '$temp'"
if ! git checkout -b "$temp"; then
	zz_log e "Failed to create temporary branch"
	git checkout "$current" 2>/dev/null
	exit 1
fi

# Cherry-pick commits from source
zz_log i "Cherry-picking commits..."
# NB: iterate in the current shell (not a `... | while` subshell) so a failure
# propagates and we bail out before the destructive reset of the source branch.
failed=0
for commit in $commits; do
	if ! git cherry-pick "$commit" --strategy=recursive -X theirs --allow-empty; then
		zz_log e "Cherry-pick failed on commit $commit"
		failed=1
		break
	fi
done

# Check if cherry-pick succeeded
if [ $failed -eq 1 ]; then
	zz_log e "Please resolve conflicts and run 'git cherry-pick --continue'"
	zz_log e "Or run 'git cherry-pick --abort' to cancel"
	exit 1
fi

# Fast-forward target branch
zz_log i "Fast-forwarding '$target' branch"
if ! git checkout "$target"; then
	zz_log e "Failed to checkout '$target' branch"
	exit 1
fi

if ! git merge --ff-only "$temp"; then
	zz_log e "Failed to fast-forward '$target' branch"
	exit 1
elif [ -n "$push" ] && ! git push origin "$target"; then
	zz_log e "Failed to push '$target' branch to remote"
	exit 1
else
	zz_log i "Cleaning up temporary branch"
	git branch -D "$temp"
fi

# Reset source branch to source base
zz_log i "Resetting '$source' to source base"
if ! git checkout "$source"; then
	zz_log e "Failed to checkout '$source' branch"
	exit 1
elif ! git reset --hard "$base"; then
	zz_log e "Failed to reset '$source' branch"
	exit 1
fi

# Go back to original branch
zz_log i "Switching back to original branch '$current'"
if ! git checkout "$current"; then
	zz_log e "Failed to checkout original branch '$current'"	
	exit 1
fi

# Log success message
zz_log i "Successfully moved commits from '$source' to '$target'"
