#!/bin/sh
# zz-install [-u url [-a archive] [-b binpath] [-v version] [-s sha256]] <name>
#            [<manager>=<name>...] — install a tool, either
#   - as a system package with whichever package manager is available
#     (apt-get, apk, dnf, yum, brew, pacman, zypper, winget), escalating
#     through sudo when not root; <name> is the default package name and
#     <manager>=<name> pairs say where a manager names it differently:
#       zz-install git-flow apk=gitflow-avh dnf=gitflow yum=gitflow \
#           brew=git-flow-avh pacman=gitflow-avh
#   - or, with -u, as a downloaded binary put in the bin directory zz-bindir
#     resolves. <url> and <binpath> may use {VERSION}, {OS} (uname -s,
#     lowercased) and {ARCH} (amd64/arm64); <archive> is tar.gz|tgz|tar.xz|zip
#     (anything else: the download is the binary); <sha256> is a hash or a
#     JSON object keyed "<os>_<arch>", checked when given.

. zz-colors

# --- arguments
eval "$(zz-args "Install a tool as a system package or a downloaded binary" "$0" "$@" <<help
u url url Download URL (switches to binary install)
a archive archive Archive type: tar.gz, tgz, tar.xz, zip (default: raw binary)
b binpath binpath Binary path inside the archive (default: the tool name)
v version version Value for {VERSION} in url/binpath
s sha256 sha256 Expected sha256 (hash, or JSON object keyed <os>_<arch>)
- pkg pkg Tool name (default package name)
# overrides overrides <manager>=<name> package name overrides
help
)"

# --- parameters
[ -n "$pkg" ] || {
    zz-log e "Usage: zz-install [-u url ...] <name> [<manager>=<name>...] (-h for help)"
    exit 1
}

# --- functions

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
        zz-log e "{Purple $1} requires root/sudo, neither available"
        return 1
    fi
}

# Run a command, forwarding what it prints as operation output (zz-log o);
# keeps its status.
op() {
    _rc=0
    _out=$("$@" 2>&1) || _rc=$?
    [ -z "$_out" ] || printf '%s\n' "$_out" | zz-log o
    return "$_rc"
}

# Refresh the apt index unless it was refreshed within the last hour, so
# installing several tools in a row updates once.
apt_update() {
    find /var/lib/apt/lists -maxdepth 1 -type f -mmin -60 2>/dev/null | grep -q . && return 0
    op as_root apt-get update -qq
}

# Install the system package through the first manager found.
# Overrides are keyed by the short manager name (apt, not apt-get).
install_package() {
    for key in apt apk dnf yum brew pacman zypper winget; do
        bin=$key
        [ "$key" = apt ] && bin=apt-get
        command -v "$bin" >/dev/null 2>&1 || continue

        name=$(name_for "$key" "$@")
        zz-log i "Installing {Purple $name} via {B $key}"

        case "$key" in
        apt) apt_update && op as_root apt-get install -y -qq "$name" ;;
        apk) op as_root apk add --no-cache -q "$name" ;;
        dnf) op as_root dnf install -y -q "$name" ;;
        yum) op as_root yum install -y -q "$name" ;;
        brew) op brew install -q "$name" ;;
        pacman) op as_root pacman -S --noconfirm --needed "$name" ;;
        zypper) op as_root zypper --non-interactive --quiet install "$name" ;;
        winget) op winget install -s winget -e --name "$name" ;;
        esac
        return $?
    done

    zz-log e "No supported package manager found to install {Purple $pkg}"
    return 1
}

# Expand {VERSION}/{OS}/{ARCH} in $1; sets os and arch for the sha lookup.
expand() {
    printf '%s' "$1" | sed \
        -e "s/{VERSION}/${version}/g" \
        -e "s/{OS}/${os}/g" \
        -e "s/{ARCH}/${arch}/g"
}

# Verify file $1 against the expected sha256 $2 (no-op when empty). A JSON
# object is reduced to its "<os>_<arch>" entry first.
verify_sha256() {
    _sum=$2
    case "$_sum" in
    "{"*) _sum=$(printf '%s' "$_sum" | jq -r --arg k "${os}_${arch}" '.[$k] // empty') ;;
    esac
    [ -n "$_sum" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then
        _got=$(sha256sum "$1" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        _got=$(shasum -a 256 "$1" | cut -d' ' -f1)
    else
        zz-log e "No sha256sum/shasum available to verify {U $1}"
        return 1
    fi
    [ "$_got" = "$_sum" ] || {
        zz-log e "Checksum mismatch for {U $1}: expected $_sum, got $_got"
        return 1
    }
}

# Download <url>, verify it, extract the binary and copy it to the bin dir.
install_download() {
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) arch=$(uname -m) ;;
    esac

    _url=$(expand "$url")
    _binpath=$(expand "${binpath:-$pkg}")

    zz-log i "Downloading {Purple $pkg} from {U $_url}"
    _tmp=$(mktemp -d)
    trap 'rm -rf "$_tmp"' EXIT
    mkdir -p "$_tmp/x"
    curl -fsSL "$_url" -o "$_tmp/dl" || {
        zz-log e "Download of {U $_url} failed"
        return 1
    }
    verify_sha256 "$_tmp/dl" "$sha256" || return 1

    case "$archive" in
    tar.gz | tgz) tar -xzf "$_tmp/dl" -C "$_tmp/x" || return 1 ;;
    tar.xz) tar -xJf "$_tmp/dl" -C "$_tmp/x" || return 1 ;;
    zip) unzip -q "$_tmp/dl" -d "$_tmp/x" || return 1 ;;
    *)
        mv "$_tmp/dl" "$_tmp/x/$pkg"
        _binpath=$pkg
        ;;
    esac

    [ -f "$_tmp/x/$_binpath" ] || {
        zz-log e "Downloaded archive for {Purple $pkg} has no {U $_binpath}"
        return 1
    }

    # zz-bindir extends PATH and sets $dir (exit 1 and an error when none is writable).
    eval "$(zz-bindir)" || return 1
    chmod +x "$_tmp/x/$_binpath"
    cp "$_tmp/x/$_binpath" "$dir/$pkg"
    zz-log s "Installed {Purple $pkg} to {U $dir/$pkg}"
}

# --- run
if [ -n "$url" ]; then
    install_download
else
    install_package "$@"
fi
