#!/bin/sh

# Handle parameters
eval $(
	zz_args "Discard changes made only of whitespace, blanks, quote/slash swaps" $0 "$@" <<-help
		d -         dryrun      show files that would be discarded without changing them
	help
)

# Navigate to repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null || exit 1

# Temp workspace for normalized comparisons
temp_dir=$(mktemp -d)
changed_list="$temp_dir/changed-files.list"
trap 'rm -rf "$temp_dir"' EXIT

# Compare all tracked modified files from HEAD to working tree/index
git diff --name-only --diff-filter=M HEAD -- >"$changed_list"

if [ ! -s "$changed_list" ]; then
	zz_log i "No modified tracked files found."
	exit 0
fi

normalize_file() {
	# Strip full-line comments first so line-oriented filters still work, then
	# collapse everything the tool is meant to ignore: all whitespace, quote
	# style ("/'), slash direction (\ vs /), and blank lines. The trailing awk
	# guarantees every emitted line ends in a newline, so a change that only
	# adds or removes the final newline normalizes away too.
	case "$1" in
		*.sh) sed -e '/^[[:space:]]*#/d' "$1" ;; # Remove comment lines in shell scripts
		*.yml|*.yaml) sed -e '/^[[:space:]]*#/d' "$1" ;; # Remove comment lines in YAML files
		*.md|*.markdown) sed -e '/^[[:space:]]*<!--.*-->/d' "$1" ;; # Remove HTML comments in Markdown files
		*.php) sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;; # Remove comment lines in PHP files
		*.html|*.htm) sed -e '/^[[:space:]]*<!--.*-->/d' "$1" ;; # Remove HTML comments in HTML files
		*.css) sed -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;; # Remove comment lines in CSS files
		*.js) sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;; # Remove comment lines in JavaScript files
		*.json) normalize-json -c -a -i -t 4 -f local -l true "$1" 2>/dev/null || cat "$1" ;; # Normalize JSON to stdout; fall back to raw content if normalization fails (never emit empty, which would be a false match)
		*) cat "$1" ;;
	esac | sed -e 's/[[:space:]]//g' -e "s/[\"']/\"/g" -e 's#[\\/]#/#g' -e '/^$/d' | awk '{ print }' # strip whitespace, unify quotes/slashes, drop blank lines, force trailing newline
}

discarded=0
kept=0
skipped=0

while IFS= read -r file; do
	# Ensure the file still exists in the working tree.
	if [ ! -f "$file" ]; then
		skipped=$((skipped + 1))
		continue
	fi

	extension="${file##*.}"
	old_file="$temp_dir/old-$discarded-$kept-$skipped.$extension"
	new_file="$temp_dir/new-$discarded-$kept-$skipped.$extension"
	norm_old="$temp_dir/norm-old-$discarded-$kept-$skipped.$extension"
	norm_new="$temp_dir/norm-new-$discarded-$kept-$skipped.$extension"

	if ! git show "HEAD:$file" >"$old_file" 2>/dev/null; then
		skipped=$((skipped + 1))
		continue
	fi

	cp "$file" "$new_file"

	# Ignore non-text files.
	if ! grep -Iq . "$old_file" || ! grep -Iq . "$new_file"; then
		skipped=$((skipped + 1))
		continue
	fi

	normalize_file "$old_file" >"$norm_old"
	normalize_file "$new_file" >"$norm_new"

	if cmp -s "$norm_old" "$norm_new"; then
		discarded=$((discarded + 1))
		zz_log i "Discarding ignorable-only changes in $file"
		if [ -z "$dryrun" ]; then
			git checkout HEAD -- "$file"
		fi
	else
		kept=$((kept + 1))
	fi
done <"$changed_list"

if [ -n "$dryrun" ]; then
	zz_log s "Dry run complete. Discardable files: $discarded, kept: $kept, skipped: $skipped"
else
	zz_log s "Done. Discarded: $discarded, kept: $kept, skipped: $skipped"
fi
