#!/bin/sh
# zz_install <pkg> [<manager>=<name>...] — install a system package with
# whichever package manager is available (apt-get, apk, dnf, yum, brew,
# pacman, zypper), escalating through sudo when not root.
#
# <pkg> is the default package name. Append <manager>=<name> pairs where
# a manager names it differently, e.g.:
#   zz_install git-flow apk=gitflow-avh dnf=gitflow yum=gitflow \
#       brew=git-flow-avh pacman=gitflow-avh

. zz_colors

[ -n "$1" ] || {
    zz_log e "Usage: zz_install <pkg> [<manager>=<name>...]"
    exit 1
}

pkg=$1
shift

# Package name for manager $1: its <manager>=<name> override, else <pkg>.
name_for() {
    _key=$1
    shift
    for _arg in "$@"; do
        case "$_arg" in
        "$_key"=*)
            echo "${_arg#*=}"
            return
            ;;
        esac
    done
    echo "$pkg"
}

# Run a command as root: directly, through sudo, or fail.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        zz_log e "{Purple $1} requires root/sudo, neither available"
        return 1
    fi
}

# Overrides are keyed by the short manager name (apt, not apt-get)
for key in apt apk dnf yum brew pacman zypper; do
    bin=$key
    [ "$key" = apt ] && bin=apt-get
    command -v "$bin" >/dev/null 2>&1 || continue

    name=$(name_for "$key" "$@")
    zz_log i "Installing {Purple $name} via $key..."

    case "$key" in
    apt) as_root apt-get update -qq && as_root apt-get install -y -qq "$name" ;;
    apk) as_root apk add --no-cache -q "$name" ;;
    dnf) as_root dnf install -y -q "$name" ;;
    yum) as_root yum install -y -q "$name" ;;
    brew) brew install -q "$name" ;;
    pacman) as_root pacman -S --noconfirm --needed "$name" ;;
    zypper) as_root zypper --non-interactive --quiet install "$name" ;;
    esac
    exit $?
done

zz_log e "No supported package manager found to install {Purple $pkg}."
exit 1
