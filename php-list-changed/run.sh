#!/bin/sh

eval $(
    zz-args "List PHP test parts (core, modules, packages) affected by a change" $0 "$@" <<-help
        b   base    base    Base ref to diff against (default: origin/\$GITHUB_BASE_REF, origin/develop, origin/main)
        f   format  format  Output format: names (default), paths, suites or json
        a   -       all     Ignore the diff and select every part
help
)

cd "$(git rev-parse --show-toplevel)" || exit 1

# Root-level paths whose change can affect every part
SHARED='^(app|bootstrap|config|database|routes|resources|public|\.github)/|^(composer\.json|composer\.lock|phpunit\.xml|phpunit\.xml\.dist|\.env\.example)$|^tests/(Pest|TestCase)\.php$'

# Part directories, from the composer merge-plugin globs (one per line)
list_parts() {
    jq -r '.extra["merge-plugin"].include[]? // empty' composer.json 2>/dev/null |
        sed 's|/composer\.json$||' |
        while read -r glob; do
            for dir in $glob; do
                [ -f "$dir/composer.json" ] && echo "$dir"
            done
        done | sort -u
}

pkg_name() { jq -r '.name // empty' "$1/composer.json"; }

# Parts requiring the package named $2, one per line
dependents() {
    for dir in $1; do
        if jq -e --arg n "$2" '(.require // {}) | has($n)' "$dir/composer.json" >/dev/null 2>&1; then
            echo "$dir"
        fi
    done
}

resolve_base() {
    for ref in "$base" "${GITHUB_BASE_REF:+origin/$GITHUB_BASE_REF}" origin/develop origin/main develop main; do
        [ -n "$ref" ] && git rev-parse --verify -q "$ref^{commit}" >/dev/null && echo "$ref" && return 0
    done
    return 1
}

parts=$(list_parts)
selected=""

if [ "$all" = "-a" ]; then
    selected="core
$parts"
else
    ref=$(resolve_base) || {
        zz-log e "No base ref found" 2>/dev/null || echo "No base ref found" >&2
        exit 1
    }
    changed=$(git diff --name-only "$(git merge-base "$ref" HEAD)" 2>/dev/null)

    if echo "$changed" | grep -Eq "$SHARED"; then
        selected="core
$parts"
    else
        echo "$changed" | grep -q '^tests/' && selected="core"
        for dir in $parts; do
            echo "$changed" | grep -q "^$dir/" && selected="$selected
$dir"
        done
        # Expand to dependents until stable
        prev=""
        while [ "$prev" != "$selected" ]; do
            prev="$selected"
            for dir in $prev; do
                [ "$dir" = core ] && continue
                name=$(pkg_name "$dir")
                [ -n "$name" ] && selected="$selected
$(dependents "$parts" "$name")"
            done
            selected=$(echo "$selected" | sed '/^$/d' | sort -u)
        done
    fi
fi

# Keep only parts that have tests to run
selected=$(echo "$selected" | sed '/^$/d' | sort -u | while read -r dir; do
    if [ "$dir" = core ]; then
        [ -d tests/Unit ] || [ -d tests/Feature ] && echo core
    elif [ -d "$dir/tests" ]; then
        echo "$dir"
    fi
done)

suite_of() {
    if [ "$1" = core ]; then echo "Unit,Feature"; else basename "$1"; fi
}

case "$format" in
json)
    echo "$selected" | sed '/^$/d' | while read -r dir; do
        jq -nc --arg n "$dir" --arg s "$(suite_of "$dir")" '{name:$n,suite:$s,path:(if $n=="core" then "tests" else $n+"/tests" end)}'
    done | jq -sc '.'
    ;;
paths)
    echo "$selected" | sed '/^$/d' | while read -r dir; do
        if [ "$dir" = core ]; then echo tests; else echo "$dir/tests"; fi
    done
    ;;
suites)
    echo "$selected" | sed '/^$/d' | while read -r dir; do suite_of "$dir"; done
    ;;
*)
    echo "$selected" | sed '/^$/d'
    ;;
esac
