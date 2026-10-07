#!/bin/sh

eval $(
	zz-args "Redact a secret from files, commit messages and/or tag annotations across all git history" $0 "$@" <<-help
		f -      force      allow overwriting pushed history
		p -      push       push to remote
		d -      dryrun     list matching commits/files without rewriting history
		g glob   glob       glob pattern of files to search (e.g. "**/*.env")
		s secret secret     secret value to redact
		r repl   replace    replacement string (default: ****)
		m -      fixmsg     also redact the secret from commit messages
		t -      fixtags    also redact the secret from tag annotation messages
		- sha    sha        sha commit to fix from (use 0 for the very first commit)
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git fetch --progress --prune --recurse-submodules=no origin >/dev/null

if [ -z "$glob" ]; then
	glob=$(zz-prompt "Glob pattern of files to search (e.g. **/*.env):")
fi

if [ -z "$glob" ]; then
	zz-log e "A glob pattern is required."
	exit 1
fi

if [ -z "$secret" ]; then
	secret=$(zz-prompt "Secret value to redact:")
fi

if [ -z "$secret" ]; then
	zz-log e "A secret value is required."
	exit 1
fi

replace="${replace:-****}"

if ! git diff-index --quiet HEAD --; then
	zz-log e "You have uncommitted changes. Please commit or stash them before running this script."
	exit 1
fi

if git isRebase >/dev/null 2>&1; then
	zz-log e "A rebase is in progress. Please finish or abort it before running this script."
	exit 1
fi

sha=$(git getcommit $force $sha)

zz-log i "Searching for secret in files matching '$glob'"

file_matches=$(git grep -I -l -F "$secret" $(git rev-list --branches --tags ${sha:---all}${sha:+..HEAD}) -- "$glob" 2>/dev/null)

msg_matches=""
if [ -n "$fixmsg" ]; then
	msg_matches=$(git log --branches --tags ${sha:---all}${sha:+..HEAD} -F --grep="$secret" --oneline)
fi

tag_matches=""
if [ -n "$fixtags" ]; then
	for t in $(git tag -l); do
		msg=$(git for-each-ref --format='%(contents)' "refs/tags/$t" 2>/dev/null)
		if printf '%s' "$msg" | grep -qF "$secret"; then
			tag_matches="$tag_matches$t
"
		fi
	done
fi

if [ -z "$file_matches" ] && [ -z "$msg_matches" ] && [ -z "$tag_matches" ]; then
	zz-log s "No occurrences of the secret found."
	exit 0
fi

[ -n "$file_matches" ] && zz-log - "Files:" && zz-log - "$file_matches"
[ -n "$msg_matches" ] && zz-log - "Commit messages:" && zz-log - "$msg_matches"
[ -n "$tag_matches" ] && zz-log - "Tag annotations:" && zz-log - "$tag_matches"

if [ -n "$dryrun" ]; then
	zz-log i "Dry run complete. No changes were made."
	exit 0
fi

zz-log w "This will rewrite git history. Make sure you understand the consequences."
if [ "$(zz-ask "Yn" "Do you want to proceed?")" != "y" ]; then
	zz-log i "Operation cancelled by user."
	exit 1
fi

# Escape the secret so it is matched literally by sed, not as a regex
sed_escape_pattern() {
	printf '%s' "$1" \
		| sed -e 's/\\/\\\\/g' \
		      -e 's/\//\\\//g' \
		      -e 's/\./\\./g' \
		      -e 's/\*/\\*/g' \
		      -e 's/\[/\\[/g' \
		      -e 's/\^/\\^/g' \
		      -e 's/\$/\\$/g'
}

# Escape the replacement so it is inserted literally by sed
sed_escape_replacement() {
	printf '%s' "$1" \
		| sed -e 's/\\/\\\\/g' \
		      -e 's/\//\\\//g' \
		      -e 's/&/\\&/g'
}

esc_secret=$(sed_escape_pattern "$secret")
esc_replace=$(sed_escape_replacement "$replace")
export SED_EXPR="s/${esc_secret}/${esc_replace}/g"
export GLOB_PATTERN="$glob"

tree_filter='
	git ls-files -- "$GLOB_PATTERN" | while IFS= read -r file; do
		[ -f "$file" ] || continue
		grep -Iq . "$file" 2>/dev/null || continue
		sed -i "$SED_EXPR" "$file"
	done
'

if [ -n "$fixmsg" ]; then
	msg_filter='sed "$SED_EXPR"'
else
	msg_filter='cat'
fi

git filter-branch $force --tree-filter "$tree_filter" --msg-filter "$msg_filter" --tag-name-filter cat -- --branches --tags ${sha:---all}${sha:+..HEAD}

# filter-branch leaves rewritten refs behind; purge them so the old history is unreachable
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

# filter-branch does not rewrite tag content, so redact annotated tag messages separately

if [ -n "$fixtags" ]; then
	zz-log i "Redacting secret from tag annotations"
	for t in $(git tag -l); do
		obj_type=$(git cat-file -t "refs/tags/$t" 2>/dev/null)
		if [ "$obj_type" = "tag" ]; then
			msg=$(git for-each-ref --format='%(contents)' "refs/tags/$t")
			if printf '%s' "$msg" | grep -qF "$secret"; then
				new_msg=$(printf '%s' "$msg" | sed "$SED_EXPR")
				target=$(git rev-list -n 1 "$t")
				tagger_name=$(git for-each-ref --format='%(taggername)' "refs/tags/$t")
				tagger_email=$(git for-each-ref --format='%(taggeremail)' "refs/tags/$t" | sed -e 's/^<//' -e 's/>$//')
				tagger_date=$(git for-each-ref --format='%(taggerdate:iso-strict)' "refs/tags/$t")
				GIT_COMMITTER_NAME="$tagger_name" GIT_COMMITTER_EMAIL="$tagger_email" GIT_COMMITTER_DATE="$tagger_date" \
					git tag -f -a "$t" "$target" -m "$new_msg"
			fi
		fi
	done
fi

if [ -n "$push" ]; then
	zz-log i "Pushing changes to remote"
	git push --force --progress --recurse-submodules=no origin --all
	git push --force --progress --recurse-submodules=no origin --tags
else
	zz-log w "Changes are not pushed to remote, use -p option to push"
fi

zz-log s "Secret replaced with '$replace' in history."
