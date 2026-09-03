#!/bin/sh

# This script performs a squash merge of the current feature branch into the develop branch.
# It enforces conventional commit message standards, handles breaking changes, and optionally pushes to remote.

# Parse arguments and print help if needed
eval $(
    zz_args "Release squashed current branch to develop branch" $0 "$@" <<-help
        m  msg     msg      Message to use for the squash merge commit
        o  -       occ      Override the commit message to use the most occurring commit type
        p  -       push     Push the changes to the remote repository after merging
help
)

# Ensure commit message is provided
if [ -z "$msg" ]; then
    zz_log e "You must provide a message for the squash merge commit using the -m option."
    exit 1
fi

# Change to repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Get the current branch name
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Ensure the script is run from a feature branch (enforces workflow discipline)
if ! echo "$current_branch" | grep -qE "^feature/"; then
    zz_log e "You must be on a feature/xxx branch to release unstable version"
    zz_log i "Current branch: $current_branch"
    exit 1
fi

# Extract feature name from branch
feature=$(echo "$current_branch" | sed 's/^feature\///')

# Update the commit message to include the feature name as a scope (conventional commit)
msg=$(echo "$msg" | sed -E "s/^([a-z]+):/\1($feature):/")

# Stash any uncommitted changes before proceeding
zz_log i "Stashing current changes..."
stash="Before finishing $current_branch branch"
git stash push --include-untracked -m "$stash"

# Check for breaking changes in commit messages and update the commit message accordingly
if git log "$current_branch" --pretty=format:"%s" | grep -Eq "(\!:)" || git log --grep="BREAKING-CHANGE" --oneline "$current_branch" --grep="BREAKING CHANGE" | grep -q .; then
    zz_log w "Breaking change found in $current_branch commit messages"
    zz_log - "updating conventional commit message to reflect this..."
    # Add '!' to the commit type if not already present
    msg=$(echo $msg | sed -E 's/^([a-z]+(\([^)]+\))?):/\1!:/')
else
    zz_log s "No breaking change found in commit messages"
fi

all_types=$(git log "$current_branch" --pretty=format:"%s" | grep -oE "^([a-z]+)" | sort | uniq -c | sort -nr)

# If all commit messages start with the same conventional commit type, start the commit message with that type.
# Else keep the most occurring first word.
# Else force "feat" if at least one commit message starts with "feat"
if echo "$all_types" | wc -l | grep -q '^1$'; then
    first_word=$(echo "$all_types" | awk '{print $2}')
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz_log i "All commit messages start with '$first_word', updating commit message to start with it..."
elif [ -n "$occ" ]; then
    first_word=$(echo "$all_types" | head -n 1 | awk '{print $2}')
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz_log i "Most occurring first word is '$first_word', updating commit message to start with it..."
elif echo "$all_types" | grep -q '^ *feat'; then
    first_word=feat
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz_log i "At least one commit message starts with 'feat', updating commit message to start with it..."
else
    zz_log i "No specific commit type found, keeping message as is..."
fi

# Prevent git editor prompt during commit
export GIT_EDITOR=:

# Perform the squash merge of the feature branch into develop

zz_log i "Finishing $current_branch with squash merge to develop..."
git fetch origin || zz_log w "Failed to fetch origin"

if ! git checkout develop; then
    zz_log e "Failed to checkout develop branch"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

if ! git merge --squash "$current_branch"; then
    zz_log e "Failed to squash merge $current_branch into develop"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

if ! git commit -m "$msg"; then
    zz_log e "Failed to commit squash merge for $current_branch"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

# Restore stashed changes and log result
zz_log s "Feature $feature successfully finished and squashed to develop"

# Restore stashed changes if any
git stash list | grep -q "$stash" && git stash pop

# Push changes to remote if requested
if [ -n "$push" ]; then
    zz_log i "Pushing changes to remote repository..."
    git push origin develop &&
        zz_log s "Changes pushed to remote repository successfully" ||
        zz_log e "Failed to push changes to remote repository"
fi

# Switch back to the original feature branch
git checkout "$current_branch"
