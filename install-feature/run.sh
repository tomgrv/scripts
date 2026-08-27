#!/bin/sh
# Install mode: copy a feature's stubs/config/bin into a target directory,
# run its install-*.sh lifecycle scripts, and symlink bin/ scripts onto a
# writable PATH directory. Counterpart to configure-feature.sh.

zz_use zz_colors zz_args zz_bindir
. zz_colors

eval $(
    zz_args "Install a feature" $0 "$@" <<-help
    s source    source      Force source directory
    t target    target      Force target directory
    - arg       arg         Caller script path
help
)

# Rebuild a clean argument list before delegating to resolve-context: several
# install-*.sh scripts re-parse "$@" themselves via resolve-context, whose
# spec has no -i flag of its own here.
set -- ${source:+-s "$source"} ${target:+-t "$target"} ${arg:+"$arg"}

eval $(
    resolve-context "$@"
)

if [ -z "$feature" ]; then
    echo "Usage: install-feature <caller>${End}"
    exit 1
fi

zz_log i "Installing feature {Purple $feature}..."

if [ -d $source/stubs ]; then
    zz_log i "Copying stubs to {U $target}..."
    cp -a $source/stubs $target
else
    zz_log w "No stubs found in {U $source}"
fi

if [ -d $source/config ]; then
    zz_log i "Copying config to {U $target}..."
    cp -a $source/config $target
fi

if [ -d $source/bin ]; then
    zz_log i "Copying bin scripts to {U $target}..."
    cp -a $source/bin $target
fi

find $source -maxdepth 1 -name "configure-*.sh" -type f -exec cp {} $target \;
find $target -type f -name "*.sh" -exec chmod +x {} \;

find $source -maxdepth 1 -type f -name "install-*.sh" | while read script; do
    zz_log i "Calling {U $script}..."
    # Invoke via `sh "$script" "$@"` (not `sh -c "$script $@"`) so a
    # multi-element "$@" forwards correctly regardless of element count.
    sh "$script" "$@" && zz_log s "Done!" || zz_log e "Failed!"
done

### Symlink bin/ scripts onto a writable PATH directory ###

zz_log i "Installing bin scripts for {Purple $feature}..."
zz_log i "Finding writable bin directory..."

eval "$(zz_bindir -t "$target")"
link_dir="$dir"

find "$target/bin" -type f -name "*.sh" 2>/dev/null | while IFS= read -r file; do
    link="$link_dir/$(basename "$file" | sed 's/.sh$//')"
    ln -sf "$file" "$link" && zz_log s "Linked {U $file} to {U $link}"
done
