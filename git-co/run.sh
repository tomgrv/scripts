#!/bin/sh

eval $(
    zz-args "git enhanced commit" $0 "$@" <<-help
        n -         noscope     Enforce no scope in commit message
        s scope     scope       Scope to use in commit message
        b branch    branch      Branch to commit to
		+ msg       msg         Commit message
	help
)

if [ -z "$msg" ]; then
    zz-log e "Commit message is required"
    exit 1
fi

if [ -z "$noscope" ] && [ -z "$scope" ]; then

    zz-log i "No scope provided, using current branch name as scope"

    prefix=$(git config gitflow.prefix.feature)

    if [ -n "$prefix" ]; then
        scope=$(git rev-parse --abbrev-ref HEAD | grep "^$prefix" | sed "s|$prefix||")
    fi
fi

if echo $msg | grep -q '^[^(]*([^)]*)'; then
    zz-log w "Scope already set in commit message"
elif [ -n "$scope" ]; then
    zz-log i "Injecting scope {B $scope} into commit message"
    msg="$(echo "$msg" | sed 's/:.*$//')($scope): $(echo "$msg" | sed 's/^[^:]*://')"
elif [ -n "$noscope" ]; then
    zz-log i "Removing scope from commit message"
    msg="$(echo "$msg" | sed 's/^[^(]*([^)]*)//')"
fi

git commit -m "$msg"

if [ -n "$branch" ]; then
    zz-log i "Rebasing branch $branch on top of current branch"
    git stash && git rebase $branch && git stash pop
fi
