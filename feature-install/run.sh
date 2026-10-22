#!/bin/sh
# Copies a feature's stubs/config/bin into a target directory, runs its
# install-*.sh lifecycle scripts, and symlinks bin/ scripts onto a writable
# PATH directory. Counterpart to feature-configure.sh.

. zz-colors

eval $(
    zz-args "Install a feature" $0 "$@" <<help
    s source    source      Force source directory
    t target    target      Force target directory
    - arg       arg         Caller script path
help
)

# Rebuild a clean argument list before delegating to feature-context: several
# install-*.sh scripts re-parse "$@" themselves via feature-context, whose
# spec has no -i flag of its own here.
set -- ${source:+-s "$source"} ${target:+-t "$target"} ${arg:+"$arg"}

# --- parameters: feature-context derives the feature, source and target
# directories; the feature name is mandatory
eval $(
    feature-context "$@"
)

if [ -z "$feature" ]; then
    echo "Usage: feature-install <caller>${End}"
    exit 1
fi

# --- step: install the feature
zz-log i "Installing feature {Purple $feature}"

# --- step: copy stubs, config and bin scripts into the target, and make the
# shell scripts executable
if [ -d $source/stubs ]; then
    cp -a $source/stubs $target && zz-log - "Copied stubs to {U $target}" || install_failed=1
else
    zz-log w "No stubs found in {U $source}"
fi

if [ -d $source/config ]; then
    cp -a $source/config $target && zz-log - "Copied config to {U $target}" || install_failed=1
fi

if [ -d $source/bin ]; then
    cp -a $source/bin $target && zz-log - "Copied bin scripts to {U $target}" || install_failed=1
fi

find $source -maxdepth 1 -name "configure-*.sh" -type f -exec cp {} $target \;
find $target -type f -name "*.sh" -exec chmod +x {} \;

# --- step: run the feature's install-*.sh lifecycle scripts
scripts=$(find $source -maxdepth 1 -type f -name "install-*.sh")
if [ -n "$scripts" ]; then
    zz-log i "Running install scripts"
fi
scripts_failed=
while read script; do
    [ -n "$script" ] || continue
    # Invoke via `sh "$script" "$@"` (not `sh -c "$script $@"`) so a
    # multi-element "$@" forwards correctly regardless of element count.
    sh "$script" "$@" && zz-log - "Ran {U $script}" || {
        scripts_failed=1
        zz-log e "Failed {U $script}"
    }
done <<EOF
$scripts
EOF
if [ -n "$scripts" ] && [ -n "$scripts_failed" ]; then
    zz-log e "Ran install scripts with errors"
elif [ -n "$scripts" ]; then
    zz-log s "Ran install scripts"
fi

# --- step: link the bin scripts onto a writable PATH directory
eval "$(zz-bindir -t "$target")"
link_dir="$dir"

bins=$(find "$target/bin" -type f -name "*.sh" 2>/dev/null)
if [ -n "$bins" ]; then
    zz-log i "Linking bin scripts"
fi
links_failed=
while IFS= read -r file; do
    [ -n "$file" ] || continue
    link="$link_dir/$(basename "$file" | sed 's/.sh$//')"
    ln -sf "$file" "$link" && zz-log - "Linked {U $file} to {U $link}" || {
        links_failed=1
        zz-log e "Failed to link {U $file} to {U $link}"
    }
done <<EOF
$bins
EOF
if [ -n "$bins" ] && [ -n "$links_failed" ]; then
    zz-log e "Linked bin scripts with errors"
elif [ -n "$bins" ]; then
    zz-log s "Linked bin scripts"
fi

# --- step: done
if [ -n "$install_failed$scripts_failed$links_failed" ]; then
    zz-log e "Installed feature {Purple $feature} with errors"
else
    zz-log s "Installed feature {Purple $feature}"
fi
