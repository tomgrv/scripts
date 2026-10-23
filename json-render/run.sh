#!/bin/sh
set -e

. zz-colors

eval $(
    zz-args "Render a JSON file: fill its \${NAME} placeholders" $0 "$@" <<help
        - file        file          JSON file holding \${NAME} placeholders
        # vars        NAME[=value]  names to fill (NAME:=json inserts raw JSON); the value comes from the environment when omitted
help
)

# --- parameters
if [ -z "$file" ]; then
    zz-log e "Usage: json-render <file> [NAME[=value] | NAME:=json]..."
    exit 1
fi
if [ ! -f "$file" ]; then
    zz-log e "File {U $file} not found"
    exit 1
fi

# --- sed script: one substitution per listed name, others left untouched
script=""
for spec in "$@"; do
    raw=""
    case "$spec" in
        *:=*)
            name="${spec%%:=*}"
            value="${spec#*:=}"
            raw=1
            ;;
        *=*)
            name="${spec%%=*}"
            value="${spec#*=}"
            ;;
        *)
            name="$spec"
            value="$(eval "printf '%s' \"\${$name:-}\"")"
            ;;
    esac
    case "$name" in
        '' | [0-9]* | *[!A-Za-z0-9_]*)
            zz-log e "Invalid placeholder name {U $name}"
            exit 1
            ;;
    esac
    if [ -n "$raw" ]; then
        # NAME:=json: the value is JSON and goes in as is (compacted)
        value="$(printf '%s' "$value" | jq -ce .)" || {
            zz-log e "Value of {U $name} is not valid JSON"
            exit 1
        }
    else
        # NAME=value: a string's content, escaped so it fits between the template's quotes
        value="$(printf '%s' "$value" | jq -Rs . | sed 's/^"//;s/"$//')"
    fi
    # \, & and the | delimiter are special in a sed replacement
    escaped="$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')"
    script="${script}s|\\\${${name}}|${escaped}|g;"
done

sed "$script" "$file"
