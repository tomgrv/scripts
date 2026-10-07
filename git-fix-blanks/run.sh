#!/bin/sh

eval $(
	zz-args "Discard changes made only of whitespace, blanks, quote/slash swaps" $0 "$@" <<-help
		d -         dryrun      show files that would be discarded without changing them
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null || exit 1

temp_dir=$(mktemp -d)
changed_list="$temp_dir/changed-files.list"
trap 'rm -rf "$temp_dir"' EXIT

git diff --name-only --diff-filter=M HEAD -- >"$changed_list"

if [ ! -s "$changed_list" ]; then
	zz-log i "No modified tracked files found."
	exit 0
fi

normalize_file() {
	# Strip full-line comments first so line-oriented filters still work, then
	# collapse everything the tool is meant to ignore: all whitespace, quote
	# style ("/'), slash direction (\ vs /), and blank lines. The trailing awk
	# guarantees every emitted line ends in a newline, so a change that only
	# adds or removes the final newline normalizes away too.
	case "$1" in
		*.sh) sed -e '/^[[:space:]]*#/d' "$1" ;;
		*.yml|*.yaml) sed -e '/^[[:space:]]*#/d' "$1" ;;
		*.md|*.markdown) sed -e '/^[[:space:]]*<!--.*-->/d' "$1" ;;
		*.php) sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;;
		*.html|*.htm) sed -e '/^[[:space:]]*<!--.*-->/d' "$1" ;;
		*.css) sed -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;;
		*.js) sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/d' -e '/^[[:space:]]*\*/d' "$1" ;;
		*.json) json-normalize -c -a -i -t 4 -f local -l true "$1" 2>/dev/null || cat "$1" ;; # fall back to raw content if normalization fails (never emit empty, which would be a false match)
		*) cat "$1" ;;
	esac | sed -e 's/[[:space:]]//g' -e "s/[\"']/\"/g" -e 's#[\\/]#/#g' -e '/^$/d' | awk '{ print }'
}

discarded=0
kept=0
skipped=0

while IFS= read -r file; do
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
		zz-log i "Discarding ignorable-only changes in $file"
		if [ -z "$dryrun" ]; then
			git checkout HEAD -- "$file"
		fi
	else
		kept=$((kept + 1))
	fi
done <"$changed_list"

if [ -n "$dryrun" ]; then
	zz-log s "Dry run complete. Discardable files: $discarded, kept: $kept, skipped: $skipped"
else
	zz-log s "Done. Discarded: $discarded, kept: $kept, skipped: $skipped"
fi
