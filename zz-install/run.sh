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
eval "$(
    zz-args "Install a tool as a system package or a downloaded binary" "$0" "$@" <<help
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

# get_package_name <manager> [<manager>=<name>...]: package name for a manager:
# its <manager>=<name> override, else <pkg>.
get_package_name() {
    local manager="$1" # short manager name, e.g. apt (mandatory)
    local override

    shift
    for override in "$@"; do
        case "$override" in
        "$manager"=*)
            echo "${override#*=}"
            return
            ;;
        esac
    done
    echo "$pkg"
}

# run_as_root <command> [args...]: run a command as root: directly, through
# sudo, or fail.
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        zz-log e "{Purple $1} requires root/sudo, neither available"
        return 1
    fi
}

# run_op <command> [args...]: run a command, forwarding what it prints as
# operation output (zz-log o); keeps its status.
run_op() {
    local rc=0
    local out

    out=$("$@" 2>&1) || rc=$?
    [ -z "$out" ] || printf '%s\n' "$out" | zz-log o
    return "$rc"
}

# update_apt: refresh the apt index unless it was refreshed within the last
# hour, so installing several tools in a row updates once.
update_apt() {
    find /var/lib/apt/lists -maxdepth 1 -type f -mmin -60 2>/dev/null | grep -q . && return 0
    run_op run_as_root apt-get update -qq
}

# install_package [<manager>=<name>...]: install the system package through
# the first manager found. Overrides are keyed by the short manager name (apt,
# not apt-get).
install_package() {
    local key bin name

    for key in apt apk dnf yum brew pacman zypper winget; do
        bin=$key
        [ "$key" = apt ] && bin=apt-get
        command -v "$bin" >/dev/null 2>&1 || continue

        name=$(get_package_name "$key" "$@")
        zz-log - "Installing {Purple $name} via {B $key}"

        case "$key" in
        apt) update_apt && run_op run_as_root apt-get install -y -qq "$name" ;;
        apk) run_op run_as_root apk add --no-cache -q "$name" ;;
        dnf) run_op run_as_root dnf install -y -q "$name" ;;
        yum) run_op run_as_root yum install -y -q "$name" ;;
        brew) run_op brew install -q "$name" ;;
        pacman) run_op run_as_root pacman -S --noconfirm --needed "$name" ;;
        zypper) run_op run_as_root zypper --non-interactive --quiet install "$name" ;;
        winget) run_op winget install -s winget -e --name "$name" ;;
        esac
        return $?
    done

    zz-log e "No supported package manager found to install {Purple $pkg}"
    return 1
}

# expand_template <text>: expand {VERSION}/{OS}/{ARCH} in <text>, from the
# script-wide version, os and arch (the last two set by install_download).
expand_template() {
    local text="$1" # text holding the placeholders (mandatory)

    printf '%s' "$text" | sed \
        -e "s/{VERSION}/${version}/g" \
        -e "s/{OS}/${os}/g" \
        -e "s/{ARCH}/${arch}/g"
}

# verify_sha256 <file> <expected>: verify a file against the expected sha256
# (no-op when empty). A JSON object is reduced to its "<os>_<arch>" entry first.
verify_sha256() {
    local target="$1" # file to check (mandatory)
    local sum="$2"    # hash, or JSON object keyed <os>_<arch> (mandatory, may be empty)
    local got

    case "$sum" in
    "{"*) sum=$(printf '%s' "$sum" | jq -r --arg k "${os}_${arch}" '.[$k] // empty') ;;
    esac
    [ -n "$sum" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then
        got=$(sha256sum "$target" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        got=$(shasum -a 256 "$target" | cut -d' ' -f1)
    else
        zz-log e "No sha256sum/shasum available to verify {U $target}"
        return 1
    fi
    [ "$got" = "$sum" ] || {
        zz-log e "Checksum mismatch for {U $target}: expected $sum, got $got"
        return 1
    }
}

# install_download: download <url>, verify it, extract the binary and copy it
# to the bin dir. os and arch stay script-wide for expand_template and
# verify_sha256.
install_download() {
    local download_url binary_path tmp dir

    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) arch=$(uname -m) ;;
    esac

    download_url=$(expand_template "$url")
    binary_path=$(expand_template "${binpath:-$pkg}")

    zz-log - "Downloading {Purple $pkg} from {U $download_url}"
    tmp=$(mktemp -d)
    # Double quotes: $tmp is local, gone when the trap fires at exit.
    trap "rm -rf '$tmp'" EXIT
    mkdir -p "$tmp/x"
    curl -fsSL "$download_url" -o "$tmp/dl" || {
        zz-log e "Download of {U $download_url} failed"
        return 1
    }
    verify_sha256 "$tmp/dl" "$sha256" || return 1

    case "$archive" in
    tar.gz | tgz) tar -xzf "$tmp/dl" -C "$tmp/x" || return 1 ;;
    tar.xz) tar -xJf "$tmp/dl" -C "$tmp/x" || return 1 ;;
    zip) unzip -q "$tmp/dl" -d "$tmp/x" || return 1 ;;
    *)
        mv "$tmp/dl" "$tmp/x/$pkg"
        binary_path=$pkg
        ;;
    esac

    [ -f "$tmp/x/$binary_path" ] || {
        zz-log e "Downloaded archive for {Purple $pkg} has no {U $binary_path}"
        return 1
    }

    # zz-bindir extends PATH and sets $dir (exit 1 and an error when none is writable).
    eval "$(zz-bindir)" || return 1
    chmod +x "$tmp/x/$binary_path"
    cp "$tmp/x/$binary_path" "$dir/$pkg"
    zz-log - "Installed {Purple $pkg} to {U $dir/$pkg}"
}

# --- run
if [ -n "$url" ]; then
    install_download
else
    install_package "$@"
fi
