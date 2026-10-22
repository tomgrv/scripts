#!/bin/sh
# Configure mode: deploy a feature's stubs into the current directory
# (merging into files that already exist there) and run its
# configure-*.sh lifecycle scripts. Counterpart to feature-install.sh.

. zz-colors

eval $(
    zz-args "Configure a feature" $0 "$@" <<help
    s source    source      Force source directory
    - arg       arg         Feature name
help
)

# --- parameters: the feature name is mandatory; the source directory defaults
# to the share directory the feature was installed into
feature=$arg

if [ -z "$feature" ]; then
    echo "Usage: feature-configure <feature>${End}"
    exit 1
fi

export source=${source:-/usr/local/share/$feature}
export tabSize=4

if [ ! -d $source ]; then
    zz-log e "Source directory <$source> does not exist"
    exit 1
fi

# clean_key <file> <path>: drop one key from a JSON or YAML file (.clean KEY).
# <path> is a JSON array of steps, handed to jq/yq as data and never evaluated:
# a string is an object key, a number an array index, and an object such as
# {"name":"Deploy"} selects the first array element whose fields all match,
# the way yaml-merge identifies list items. Anything that does not resolve
# (missing file, key or element) leaves the file untouched.
clean_key() {
    ck_file=$1
    ck_path=$2

    case "${ck_file##*.}" in
    json) ck_type=json ;;
    yaml | yml) ck_type=yaml ;;
    *)
        zz-log w "Skipping KEY for {U $ck_file}: only JSON and YAML files are supported"
        return 0
        ;;
    esac

    [ -f "$ck_file" ] || return 0

    if ! printf '%s\n' "$ck_path" | jq -e 'type == "array" and length > 0 and all(.[]; type == "string" or type == "number" or (type == "object" and length > 0))' >/dev/null 2>&1; then
        zz-log w "Invalid key path {U $ck_path} for {U $ck_file}, expected a non-empty JSON array of strings, numbers or {\"field\":\"value\"} selectors"
        return 0
    fi

    if [ "$ck_type" = yaml ]; then
        if ! yq --version 2>&1 | grep -q mikefarah; then
            zz-log w "Skipping KEY for {U $ck_file}: it needs mikefarah/yq"
            return 0
        fi
        ck_doc=$(yq -o=json . "$ck_file" 2>/dev/null) || {
            zz-log w "Skipping KEY for {U $ck_file}: not valid YAML"
            return 0
        }
    else
        ck_doc=$(jq -c . "$ck_file" 2>/dev/null) || {
            zz-log w "Skipping KEY for {U $ck_file}: not valid JSON"
            return 0
        }
    fi

    ck_resolved=$(printf '%s\n' "$ck_doc" | jq -c --argjson p "$ck_path" '
        def pick($k):
            if ($k | type) == "object" then
                (.node | if type == "array" then
                    to_entries | map(select(.value as $e | ($e | type) == "object" and ($k | to_entries | all(. as $kv | $e[$kv.key] == $kv.value)))) | first
                else null end) as $m
                | if $m == null then null else {path: (.path + [$m.key]), node: $m.value} end
            elif ($k | type) == "string" then
                if (.node | type) == "object" and (.node | has($k)) then {path: (.path + [$k]), node: .node[$k]} else null end
            else
                if (.node | type) == "array" and $k >= 0 and $k < (.node | length) then {path: (.path + [$k]), node: .node[$k]} else null end
            end;
        reduce $p[] as $k ({path: [], node: .}; if . == null then null else pick($k) end)
        | if . == null then null else .path end') || return 0
    [ "$ck_resolved" != null ] || return 0

    if [ "$ck_type" = yaml ]; then
        CK_PATHS="[$ck_resolved]" yq -i -I "${tabSize:-2}" 'delpaths(env(CK_PATHS))' "$ck_file" \
            && zz-log s "Removed key {U $ck_path} from {U $ck_file}" \
            || zz-log w "Could not remove key {U $ck_path} from {U $ck_file}"
    else
        ck_tmp=$(mktemp)
        if jq --indent "${tabSize:-4}" --argjson r "$ck_resolved" 'delpaths([$r])' "$ck_file" >"$ck_tmp"; then
            cat "$ck_tmp" >"$ck_file"
            zz-log s "Removed key {U $ck_path} from {U $ck_file}"
        else
            zz-log w "Could not remove key {U $ck_path} from {U $ck_file}"
        fi
        rm -f "$ck_tmp"
    fi
}

# --- step: configure the feature
zz-log i "Configure feature <{Purple $feature}> from {U $source} in {U $(pwd)}"

# --- step: deploy the stubs into the current directory (.clean directives,
# files, symlinks); skipped when the feature ships none
if [ -d $source/stubs ]; then

    # The .clean files are walked twice: KEY directives before the merge,
    # RMV/DEL directives after it.
    cleanfiles=$(find "$source/stubs" -type f -name ".clean" | sort)
    directives=$(printf '%s\n' "$cleanfiles" | while IFS= read -r cleanfile; do
        [ -f "$cleanfile" ] && cat "$cleanfile"
    done)
    stubfiles=$(find $source/stubs -type f -name ".*" -not -name ".clean" -o -type f -not -name ".clean" | sort)
    links=$(find "$source/stubs" -type l)

    # KEY directives run BEFORE the stubs are merged: json-merge and
    # yaml-merge keep the value already in the target, so dropping a key first
    # is what lets the merge write the stub's current value in its place (a
    # fixed scalar), or leaves it gone when the stub no longer has the key.
    if printf '%s\n' "$directives" | grep -qE '^[[:space:]]*KEY([[:space:]]|$)'; then
        zz-log i "Processing .clean KEY directives"
    fi
    printf '%s\n' "$cleanfiles" | while read cleanfile; do
        [ -n "$cleanfile" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ "$(printf '%s\n' "$line" | awk '{print $1}')" = KEY ] || continue
            keyargs=$(printf '%s\n' "$line" | cut -d' ' -f2-)
            keyfile=${keyargs%% *}
            keypath=${keyargs#"$keyfile"}
            keypath=${keypath# }
            if [ -z "$keyfile" ] || [ -z "$keypath" ] || [ "$keypath" = "$keyargs" ]; then
                zz-log w "Invalid .clean directive {U $line}, expected: KEY <json-or-yaml-file> <json-array-path>"
                continue
            fi
            clean_key "$keyfile" "$keypath"
        done <"$cleanfile"
    done
    if printf '%s\n' "$directives" | grep -qE '^[[:space:]]*KEY([[:space:]]|$)'; then
        zz-log s "Processed .clean KEY directives"
    fi

    if [ -n "$stubfiles" ]; then
        zz-log i "Deploying stubs"
    fi

    # Deploy every stub file: merge it into the existing destination (JSON,
    # YAML or line-set reconciliation), or copy it when there is none yet.
    deploy_failed=
    while read file; do
        [ -n "$file" ] || continue

        folder=$(dirname ${file#$source/stubs/})
        ignored=

        base=$(basename $file | sed 's/\.\./\./g')
        case "$base" in
        _*)
            base=${base#_}
            base=${base#*.}
            ;;
        esac

        dest=$folder/$base

        # Composer files are useless (and would trigger composer hooks) without PHP
        case "$base" in
        composer.json | composer.lock)
            if ! command -v php >/dev/null 2>&1; then
                zz-log i "Skipping {U $dest}: php is not installed"
                continue
            fi
            ;;
        esac

        mkdir -p $folder

        # A dangling symlink fails every "-f $dest" test below, yet cp and
        # chmod refuse to write through it: replace it with the stub.
        if [ -L "$dest" ] && [ ! -e "$dest" ]; then
            zz-log w "Destination {U $dest} is a dangling symlink to {U $(readlink "$dest")}, replacing it..."
            rm -f "$dest"
        fi

        if [ "$(basename $file | cut -c1)" = "#" ]; then
            dest=$(echo $dest | sed 's/\/\#/\//g')
            grep -qxF $dest .gitignore || {
                echo "$dest" >>.gitignore
                ignored=", added to .gitignore"
            }
        fi

        if [ "${dest##*.}" = "json" ]; then

            if [ -f $dest ]; then
                json-merge -t ${tabSize:-4} $dest $file && how=merged || how=failed
            else
                cp $file $dest && how=copied || how=failed
            fi

        elif [ "${dest##*.}" = "yaml" ] || [ "${dest##*.}" = "yml" ]; then

            if [ -f $dest ]; then
                yaml-merge -i ${tabSize:-2} $dest $file && how=merged || how=failed
            else
                cp $file $dest && how=copied || how=failed
            fi

        else
            # Non-JSON fragments accumulate via a plain line-set
            # reconciliation, not git merge-file: merge-file's 3-way diff is
            # positional, and independent fragments routinely add their
            # distinct lines at the very same spot (end of the shared
            # common lines), which it reports as a conflict it can't order
            # rather than two additions to union. Keep a per-(feature,
            # fragment) snapshot of what was last deployed and diff the
            # incoming file against it.
            snapshot_dir=$(git rev-parse --git-path info 2>/dev/null || echo .git/info)/configure-feature/state
            snapshot=$snapshot_dir/$(printf '%s' "$feature/${file#$source/stubs/}" | sha1sum | cut -d' ' -f1)
            mkdir -p $snapshot_dir
            base=$snapshot
            [ -f $base ] || base=/dev/null

            if [ ! -f $dest ]; then
                cp $file $dest && how=copied || how=failed
            elif [ $base != /dev/null ] && [ ! $file -nt $base ]; then
                how=unchanged
            elif [ "$(head -n1 $file)" = "---" ] || [ "$(head -c2 $file)" = "#!" ] ||
                case ${dest##*/} in Dockerfile | *.xml) true ;; *) false ;; esac; then
                # A file opening with a `---` frontmatter block (SKILL.md,
                # *.instructions.md), a `#!` shebang (scripts), a Dockerfile or an XML file is a
                # single-owner document, not a fragment: its first line must
                # stay first, and the line-set reconciliation below would
                # drop or duplicate repeated lines (`fi`, `)`) and break it.
                cp $file $dest
                how=replaced
            else
                how=reconciled

                removed=$(mktemp)
                grep -vFxf $file $base >$removed
                if [ -s $removed ]; then
                    reconciled=$(mktemp)
                    grep -vFxf $removed $dest >$reconciled
                    cat $reconciled >$dest
                    rm -f $reconciled
                fi
                rm -f $removed

                added=$(mktemp)
                grep -vFxf $base $file >$added
                if [ -s $added ]; then
                    new=$(mktemp)
                    grep -vFxf $dest $added >$new
                    if [ -s $new ]; then
                        [ -z "$(tail -c1 $dest)" ] || printf '\n' >>$dest
                        cat $new >>$dest
                    fi
                    rm -f $new
                fi
                rm -f $added
            fi

            cp -p $file $snapshot
        fi

        chmod $(stat -c "%a" $file) $dest
        if [ "$how" = failed ]; then
            deploy_failed=1
            zz-log e "Failed to deploy {U $file} to {U $dest}"
        else
            zz-log - "Deployed {U $dest} ($how$ignored)"
        fi

    done <<EOF
$stubfiles
EOF

    if [ -n "$stubfiles" ] && [ -n "$deploy_failed" ]; then
        zz-log e "Deployed stubs with errors"
    elif [ -n "$stubfiles" ]; then
        zz-log s "Deployed stubs"
    fi

    # RMV and DEL directives run AFTER the merge, so they win over the stubs.
    if printf '%s\n' "$directives" | grep -qE '^[[:space:]]*(RMV|DEL)([[:space:]]|$)'; then
        zz-log i "Processing .clean files"
    fi
    printf '%s\n' "$cleanfiles" | while read cleanfile; do
        [ -n "$cleanfile" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            case "$line" in
            \#*) continue ;;
            esac

            op=$(echo "$line" | awk '{print $1}')
            path=$(echo "$line" | cut -d' ' -f2-)

            case "$op" in
            RMV)
                if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
                    git rm --cached -q -- "$path"
                    zz-log - "Untracked {U $path} (kept on disk)"
                fi
                ;;
            DEL)
                if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
                    git rm -f -q -- "$path"
                    zz-log - "Deleted {U $path} and untracked it"
                elif [ -e "$path" ]; then
                    rm -f -- "$path"
                    zz-log - "Deleted {U $path}"
                fi
                ;;
            KEY) ;; # already handled before the stubs were deployed
            *)
                zz-log w "Unknown .clean directive {U $line}, skipping"
                ;;
            esac
        done <"$cleanfile"
    done
    if printf '%s\n' "$directives" | grep -qE '^[[:space:]]*(RMV|DEL)([[:space:]]|$)'; then
        zz-log s "Processed .clean files"
    fi

    # Stub symlinks are recreated unless something already sits at the
    # destination.
    if [ -n "$links" ]; then
        zz-log i "Deploying stubs symlinks"
    fi
    printf '%s\n' "$links" | while IFS= read -r link; do
        [ -n "$link" ] || continue
        rel=${link#"$source/stubs/"}
        dest=$rel
        mkdir -p "$(dirname "$dest")"
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            target=$(readlink "$link")
            ln -s "$target" "$dest"
            zz-log - "Created symlink {U $dest} -> {U $target}"
        fi
    done
    if [ -n "$links" ]; then
        zz-log s "Deployed stubs symlinks"
    fi
fi

# --- step: run the feature's configure-*.sh lifecycle scripts, from the
# repository top level only
if [ "$(pwd)" = "$(git rev-parse --show-toplevel)" ]; then

    scripts=$(find $source -maxdepth 1 -name configure-*.sh | sort)
    if [ -n "$scripts" ]; then
        zz-log i "Running configure scripts"
    fi
    scripts_failed=
    while read file; do
        [ -n "$file" ] || continue
        sh -c "$file" && zz-log - "Ran {U $file}" || {
            scripts_failed=1
            zz-log e "Failed {U $file}"
        }
    done <<EOF
$scripts
EOF
    if [ -n "$scripts" ] && [ -n "$scripts_failed" ]; then
        zz-log e "Ran configure scripts with errors"
    elif [ -n "$scripts" ]; then
        zz-log s "Ran configure scripts"
    fi
else
    zz-log w "Not in top level directory, skipping configure scripts"
fi

# --- step: done
if [ -n "$deploy_failed$scripts_failed" ]; then
    zz-log e "Configured feature <{Purple $feature}> with errors"
else
    zz-log s "Configured feature <{Purple $feature}>"
fi
