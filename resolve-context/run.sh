#!/bin/sh
# Export source/target folders depending on feature context (which feature's
# install/configure flow is calling this, and where its files live/deploy to).

zz_use zz_colors zz_args
. zz_colors

eval $(
    zz_args "Export Source/Targets folders depending on feature context" $0 "$@" <<-help
        s source 	source		Force source directory
        t target	target		Force target directory
        - caller	caller		Force caller script
help
)

if [ -n "$source" ]; then
    source=$(readlink -f $source)
else
    if [ -z "$caller" ]; then
        caller=$(readlink -f $PWD/$(tr '\0' '\n' </proc/$PPID/cmdline | sed 's/^\/bin\/.*$//' | grep -v '^$' | head -n 1))
        zz_log - "Caller script is {U $caller}"

        if [ -z "$caller" ]; then
            zz_log e "Not in script context" && exit 1
        fi
    fi

    source=$(readlink -f $(dirname $caller))
fi

feature=$(basename $source | sed 's/_[0-9]*$//')

if [ -z "$target" ]; then
    if [ -w /usr/local/share ]; then
        target=/usr/local/share/$feature
    elif [ -w /tmp ]; then
        target=/tmp/$feature
    else
        zz_log e "No writeable directory found" && exit 1
    fi
fi

mkdir -p $target

zz_log s "Selected context for {Purple $feature} is {U $source} => {U $target}"

echo source=$source
echo feature=$feature
echo target=$target
