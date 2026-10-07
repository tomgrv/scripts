#!/bin/sh

# Squash-merges the current feature branch into develop, rewriting the
# squash commit message to conventional-commit standards (scope, breaking
# change marker, most common type), and optionally pushes to remote.

eval $(
    zz-args "Release squashed current branch to develop branch" $0 "$@" <<-help
        m  msg     msg      Message to use for the squash merge commit
        o  -       occ      Override the commit message to use the most occurring commit type
        p  -       push     Push the changes to the remote repository after merging
help
)

# Ensure commit message is provided
if [ -z "$msg" ]; then
    zz-log e "You must provide a message for the squash merge commit using the -m option."
    exit 1
fi

cd "$(git rev-parse --show-toplevel)" >/dev/null

current_branch=$(git rev-parse --abbrev-ref HEAD)

# Ensure the script is run from a feature branch (enforces workflow discipline)
if ! echo "$current_branch" | grep -qE "^feature/"; then
    zz-log e "You must be on a feature/xxx branch to release unstable version"
    zz-log i "Current branch: $current_branch"
    exit 1
fi

feature=$(echo "$current_branch" | sed 's/^feature\///')

msg=$(echo "$msg" | sed -E "s/^([a-z]+):/\1($feature):/")

zz-log i "Stashing current changes..."
stash="Before finishing $current_branch branch"
git stash push --include-untracked -m "$stash"

if git log "$current_branch" --pretty=format:"%s" | grep -Eq "(\!:)" || git log --grep="BREAKING-CHANGE" --oneline "$current_branch" --grep="BREAKING CHANGE" | grep -q .; then
    zz-log w "Breaking change found in $current_branch commit messages"
    zz-log - "updating conventional commit message to reflect this..."
    msg=$(echo $msg | sed -E 's/^([a-z]+(\([^)]+\))?):/\1!:/')
else
    zz-log s "No breaking change found in commit messages"
fi

all_types=$(git log "$current_branch" --pretty=format:"%s" | grep -oE "^([a-z]+)" | sort | uniq -c | sort -nr)

if echo "$all_types" | wc -l | grep -q '^1$'; then
    first_word=$(echo "$all_types" | awk '{print $2}')
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz-log i "All commit messages start with '$first_word', updating commit message to start with it..."
elif [ -n "$occ" ]; then
    first_word=$(echo "$all_types" | head -n 1 | awk '{print $2}')
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz-log i "Most occurring first word is '$first_word', updating commit message to start with it..."
elif echo "$all_types" | grep -q '^ *feat'; then
    first_word=feat
    msg=$(echo "$msg" | sed -E "s/^( *[a-z]+)/$first_word/")
    zz-log i "At least one commit message starts with 'feat', updating commit message to start with it..."
else
    zz-log i "No specific commit type found, keeping message as is..."
fi

export GIT_EDITOR=:

zz-log i "Finishing $current_branch with squash merge to develop..."
git fetch origin || zz-log w "Failed to fetch origin"

if ! git checkout develop; then
    zz-log e "Failed to checkout develop branch"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

if ! git merge --squash "$current_branch"; then
    zz-log e "Failed to squash merge $current_branch into develop"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

if ! git commit -m "$msg"; then
    zz-log e "Failed to commit squash merge for $current_branch"
    git stash list | grep -q "$stash" && git stash pop
    exit 1
fi

zz-log s "Feature $feature successfully finished and squashed to develop"

git stash list | grep -q "$stash" && git stash pop

if [ -n "$push" ]; then
    zz-log i "Pushing changes to remote repository..."
    git push origin develop &&
        zz-log s "Changes pushed to remote repository successfully" ||
        zz-log e "Failed to push changes to remote repository"
fi

git checkout "$current_branch"
