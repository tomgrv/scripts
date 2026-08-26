#!/bin/sh
# Configure mode: deploy a feature's stubs into the current directory
# (merging into files that already exist there) and run its
# configure-*.sh lifecycle scripts. Counterpart to install-feature.sh.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/zz_wrap.sh" 2>/dev/null || . zz_wrap
zz_use git

eval $(
    zz_args "Configure a feature" $0 "$@" <<-help
    s source    source      Force source directory
    - arg       arg         Feature name
help
)

feature=$arg

if [ -z "$feature" ]; then
    echo "Usage: configure-feature <feature>${End}"
    exit 1
fi

export source=${source:-/usr/local/share/$feature}
export tabSize=4

zz_log i "Configure feature <{Purple $feature}>"
zz_log - "In {U $(pwd)}"
zz_log - "From {U $source}"

if [ ! -d $source ]; then
    zz_log e "Source directory <$source> does not exist"
    exit 1
fi

if [ -d $source/stubs ]; then

    zz_log i "Deploying stubs..."

    find $source/stubs -type f -name ".*" -o -type f | sort | while read file; do

        folder=$(dirname ${file#$source/stubs/})

        base=$(basename $file | sed 's/\.\./\./g')
        case "$base" in
        _*)
            base=${base#_}
            base=${base#*.}
            ;;
        esac

        dest=$folder/$base

        mkdir -p $folder

        if [ "$(basename $file | cut -c1)" = "#" ]; then
            dest=$(echo $dest | sed 's/\/\#/\//g')
            zz_log - "Add {U $dest} to .gitignore"
            grep -qxF $dest .gitignore || echo "$dest" >>.gitignore
        fi

        if [ "${dest##*.}" = "json" ]; then

            if [ -f $dest ]; then
                zz_log - "Merging {U $file} into {U $dest}..."
                merge-json -t ${tabSize:-4} $dest $file
            else
                zz_log w "Destination file {U $dest} does not exist. Copying {U $file} to {U $dest}..."
                cp $file $dest
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
            snapshot_dir=$(git rev-parse --git-path info 2>/dev/null || echo .git/info)/zz_feature/state
            snapshot=$snapshot_dir/$(echo -n "$feature/${file#$source/stubs/}" | sha1sum | cut -d' ' -f1)
            mkdir -p $snapshot_dir
            base=$snapshot
            [ -f $base ] || base=/dev/null

            if [ ! -f $dest ]; then
                zz_log w "Destination file {U $dest} does not exist. Copying {U $file} to {U $dest}..."
                cp $file $dest
            elif [ $base != /dev/null ] && [ ! $file -nt $base ]; then
                zz_log - "No change in {U $file} since last deploy, skipping merge into {U $dest}"
            else
                zz_log - "Reconciling {U $file} into {U $dest}..."

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

    done

    zz_log i "Deploying stubs symlinks if existing..."

    find "$source/stubs" -type l | while IFS= read -r link; do
        rel=${link#"$source/stubs/"}
        dest=$rel
        mkdir -p "$(dirname "$dest")"
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            target=$(readlink "$link")
            zz_log - "Creating symlink {U $dest} -> {U $target}..."
            ln -s "$target" "$dest"
        fi
    done

    zz_log s "Done deploying stubs."
fi

if [ "$(pwd)" = "$(git rev-parse --show-toplevel)" ]; then

    zz_log i "Checking for configure scripts in the source directory..."

    find $source -maxdepth 1 -name configure-*.sh | sort | while read file; do
        zz_log - "Calling {U $file}..."
        sh -c "$file" && zz_log s "Done!" || zz_log e "Failed!"
    done
else
    zz_log w "Not in top level directory, skipping configure scripts"
fi
