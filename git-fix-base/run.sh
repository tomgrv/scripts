#!/bin/sh

eval $(
	zz-args "Fix git base - rebase commits from one branch to another" $0 "$@" <<-help
		    p -      push      push changes to remote
		    n -      dryrun    show what would be done without making changes
		    - target target    target branch to rebase commits onto
		    - source source    source branch to take commits from (default: current branch)
help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

if [ -z "$target" ]; then
	zz-log e 'Target branch is required. Use -h for help.'
	exit 1
elif ! git rev-parse --verify "$target" >/dev/null 2>&1; then
	zz-log e "Target branch '$target' does not exist"
	exit 1
fi

if [ -z "$source" ]; then
	source=$(git rev-parse --abbrev-ref HEAD)
	zz-log i "Using current branch as source: $source"
elif ! git rev-parse --verify "$source" >/dev/null 2>&1; then
	zz-log e "Source branch '$source' does not exist"
	exit 1
fi

if [ "$source" = "$target" ]; then
	zz-log e "Source and target branches cannot be the same: $source"
	exit 1
fi

if git isDirty; then
	zz-log e 'Working directory is not clean. Please commit or stash your changes.'
	exit 1
fi

base=$(git merge-base "$source" "$target")
if [ -z "$base" ]; then
	zz-log e "Could not find common ancestor between '$source' and '$target'"
	exit 1
else
	zz-log i "Found merge base: $base"
fi

commits=$(git log --reverse --format=%H "$source" --not origin/"$source" --not "$target" --no-merges)	

if [ -z "$commits" ]; then
	zz-log i "No commits to move from '$source' to '$target'"
	exit 0
fi

count=$(echo "$commits" | wc -l)
zz-log i "Found $count commit(s) to move from '$source' to '$target'"

if [ -n "$dryrun" ]; then
	zz-log i "Commits that would be moved:"
	echo "$commits" | while read commit; do
		if [ -n "$commit" ]; then
			echo "  $(git log --oneline -1 "$commit")"
		fi
	done
	zz-log i "To execute, run without -n flag"
	exit 0
fi

zz-log i "About to move $count commit(s) from '$source' to '$target':"
echo "$commits" | while read commit; do
	if [ -n "$commit" ]; then
		zz-log - "  $(git log --oneline -1 "$commit")" >&2
	fi
done
zz-log i "This will:"
zz-log - " 1. Checkout '$target' branch"
zz-log - " 2. Create a temporary branch for the rebase"
zz-log - " 3. Cherry-pick commits from '$source'"
zz-log - " 4. Reset '$source' to the merge base"
zz-log - " 5. Fast-forward '$target' to include the rebased commits"
echo ""
if [ "$(zz-ask "Yn" "Continue?")" != "y" ]; then
	zz-log e "Operation cancelled"
	exit 1
fi

current=$(git rev-parse --abbrev-ref HEAD)

temp="temp-fix-base-$(date +%s)"

zz-log i "Checking out '$target' branch"
if ! git checkout "$target"; then
	zz-log e "Failed to checkout '$target' branch"
	exit 1
fi

zz-log i "Creating temporary branch '$temp'"
if ! git checkout -b "$temp"; then
	zz-log e "Failed to create temporary branch"
	git checkout "$current" 2>/dev/null
	exit 1
fi

zz-log i "Cherry-picking commits..."
# NB: iterate in the current shell (not a `... | while` subshell) so a failure
# propagates and we bail out before the destructive reset of the source branch.
failed=0
for commit in $commits; do
	if ! git cherry-pick "$commit" --strategy=recursive -X theirs --allow-empty; then
		zz-log e "Cherry-pick failed on commit $commit"
		failed=1
		break
	fi
done

if [ $failed -eq 1 ]; then
	zz-log e "Please resolve conflicts and run 'git cherry-pick --continue'"
	zz-log e "Or run 'git cherry-pick --abort' to cancel"
	exit 1
fi

zz-log i "Fast-forwarding '$target' branch"
if ! git checkout "$target"; then
	zz-log e "Failed to checkout '$target' branch"
	exit 1
fi

if ! git merge --ff-only "$temp"; then
	zz-log e "Failed to fast-forward '$target' branch"
	exit 1
elif [ -n "$push" ] && ! git push origin "$target"; then
	zz-log e "Failed to push '$target' branch to remote"
	exit 1
else
	zz-log i "Cleaning up temporary branch"
	git branch -D "$temp"
fi

zz-log i "Resetting '$source' to source base"
if ! git checkout "$source"; then
	zz-log e "Failed to checkout '$source' branch"
	exit 1
elif ! git reset --hard "$base"; then
	zz-log e "Failed to reset '$source' branch"
	exit 1
fi

zz-log i "Switching back to original branch '$current'"
if ! git checkout "$current"; then
	zz-log e "Failed to checkout original branch '$current'"	
	exit 1
fi

zz-log i "Successfully moved commits from '$source' to '$target'"
