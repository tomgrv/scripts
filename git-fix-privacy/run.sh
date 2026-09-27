#!/bin/sh

eval $(
	zz_args "Fix privacy in history" $0 "$@" <<-help
		f -      force      force overwrite backup
		p -      push       push to remote
		o old    old        old email to replace
		n new    new        new name to replace with
		a author author     author name to replace with
		- sha    sha        sha commit to start from
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git fetch --progress --prune --recurse-submodules=no origin >/dev/null

if [ -z "$old" ]; then
	zz_log w "Old email is not specified, it will be taken from the last commit"
	old=$(git log -1 --pretty=format:'%ae')

	[ "$(zz_ask Yn "Do you want to proceed with this <$old> as old email?")" = "y" ] || exit 1
fi

if [ -z "$new" ]; then
	zz_log w "New email is not specified, it will be taken from the specified commit"
fi

if [ -z "$author" ]; then
	zz_log w "Author is not specified, it will be taken from the specified commit"
fi

sha=$(git getcommit $force $sha)

zz_log i "Fix privacy from commit: $sha"

if [ -n "$new" ]; then
	zz_log i "Setting new email for git config"
	git config user.email "$new"
else
	zz_log s "Take email from specified commit"
	new=$(git log -1 --pretty=format:'%ae' "$sha")
fi

if [ -n "$author" ]; then
	echo "Setting new author for git config"
	git config user.name "$author"
else
	zz_log s "Take author from specified commit"
	author=$(git log -1 --pretty=format:'%an' "$sha")
fi

git filter-branch $force --env-filter "
if [ \"\$GIT_COMMITTER_EMAIL\" = \"$old\" ]
then
    GIT_COMMITTER_NAME=\"$author\"
    GIT_COMMITTER_EMAIL=\"$new\"
fi
if [ \"\$GIT_AUTHOR_EMAIL\" = \"$old\" ]
then
    GIT_AUTHOR_NAME=\"$author\"
    GIT_AUTHOR_EMAIL=\"$new\"
fi
" --tag-name-filter cat -- --branches --tags ${sha:---all}${sha:+..HEAD}

if [ -n "$push" ]; then
	zz_log i "Pushing changes to remote"
	git push --force --progress --recurse-submodules=no origin --all
	git push --force --progress --recurse-submodules=no origin --tags
else
	zz_log w "Changes are not pushed to remote, use -p option to push"
fi

# filter-branch leaves rewritten refs behind; purge them so the old history is unreachable
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now
