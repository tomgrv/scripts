#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Redact a secret from files, commit messages and/or tag annotations across all git history" $0 "$@" <<-help
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

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Fetch updates from the remote repository
git fetch --progress --prune --recurse-submodules=no origin >/dev/null

# Check if the glob option is set
if [ -z "$glob" ]; then
	glob=$(zz_prompt "Glob pattern of files to search (e.g. **/*.env):")
fi

if [ -z "$glob" ]; then
	zz_log e "A glob pattern is required."
	exit 1
fi

# Check if the secret option is set
if [ -z "$secret" ]; then
	secret=$(zz_prompt "Secret value to redact:")
fi

if [ -z "$secret" ]; then
	zz_log e "A secret value is required."
	exit 1
fi

# Default replacement string
replace="${replace:-****}"

# Make sure we don't have uncommitted changes
if ! git diff-index --quiet HEAD --; then
	zz_log e "You have uncommitted changes. Please commit or stash them before running this script."
	exit 1
fi

# Prevent running while a rebase is in progress
if git isRebase >/dev/null 2>&1; then
	zz_log e "A rebase is in progress. Please finish or abort it before running this script."
	exit 1
fi

# Retrieve the commit SHA to fix from
sha=$(git getcommit $force $sha)

zz_log i "Searching for secret in files matching '$glob'"

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
	zz_log s "No occurrences of the secret found."
	exit 0
fi

[ -n "$file_matches" ] && zz_log - "Files:" && zz_log - "$file_matches"
[ -n "$msg_matches" ] && zz_log - "Commit messages:" && zz_log - "$msg_matches"
[ -n "$tag_matches" ] && zz_log - "Tag annotations:" && zz_log - "$tag_matches"

if [ -n "$dryrun" ]; then
	zz_log i "Dry run complete. No changes were made."
	exit 0
fi

zz_log w "This will rewrite git history. Make sure you understand the consequences."
if ! zz_ask "Yn" "Do you want to proceed?"; then
	zz_log i "Operation cancelled by user."
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

# Clean up the original refs
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

# Redact secret from annotated tag messages (filter-branch does not rewrite tag content)
if [ -n "$fixtags" ]; then
	zz_log i "Redacting secret from tag annotations"
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
	zz_log i "Pushing changes to remote"
	git push --force --progress --recurse-submodules=no origin --all
	git push --force --progress --recurse-submodules=no origin --tags
else
	zz_log w "Changes are not pushed to remote, use -p option to push"
fi

zz_log s "Secret replaced with '$replace' in history."
