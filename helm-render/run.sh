#!/bin/sh
set -e

. zz-colors

eval $(
    zz-args "Render a YAML/Helm values file: fill its \${NAME} placeholders" $0 "$@" <<help
        - file        file          YAML file holding \${NAME} placeholders
        # vars        NAME[=value]  names to fill; the value comes from the environment when omitted
help
)

# --- parameters
if [ -z "$file" ]; then
    zz-log e "Usage: helm-render <file> [NAME[=value]]..."
    exit 1
fi
if [ ! -f "$file" ]; then
    zz-log e "File {U $file} not found"
    exit 1
fi

# --- sed script: one substitution per listed name, others left untouched
script=""
for spec in "$@"; do
    case "$spec" in
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
    case "$value" in
        *'
'*)
            zz-log e "Value of {U $name} spans several lines"
            exit 1
            ;;
    esac
    # \, & and the | delimiter are special in a sed replacement
    escaped="$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')"
    script="${script}s|\\\${${name}}|${escaped}|g;"
done

sed "$script" "$file"
