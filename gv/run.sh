#!/bin/sh

# Call GitVersion against this repo's .gitversion configuration, preferring
# the Docker-based CLI when Docker is actually usable and falling back to
# the dotnet-tool CLI otherwise. Installs whichever backend it needs to use,
# on demand, the first time it's needed -- so nothing has to pre-decide
# which one a given environment gets.
#
# Both backends are tried the same way (resolve on PATH, install if
# missing, re-check) and neither branch exits on its own -- $backend is set
# only once a tool is confirmed actually resolvable, and the single case at
# the end is what invokes it or fails loudly. That keeps a failed install
# (network down, no GitVersion.Tool feed, etc.) from aborting silently
# mid-script via `set -e`: it just leaves $backend unset, so the run falls
# through to the same clear error every other "nothing worked" case hits.

set -eu

GITVERSION_VERSION="${GITVERSION_VERSION:-6.5.1}"
INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"

backend=""

# `docker info` (not just `command -v docker`) confirms a daemon is actually
# reachable -- the CLI can be on PATH with no daemon behind it (e.g. no
# docker-in-docker in this container), which would otherwise hang or fail
# on the first real `docker run`.
if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
    if ! command -v docker-gitversion > /dev/null 2>&1; then
        zz_log i "Installing docker-gitversion wrapper (gittools/gitversion:${GITVERSION_VERSION})..."
        cat > "${INSTALL_BIN_DIR}/docker-gitversion" << DOCKERWRAP || true
#!/bin/sh
cd "\$(git rev-parse --show-toplevel)" && \\
docker run --rm -v "\$(git rev-parse --show-toplevel):/repo" gittools/gitversion:${GITVERSION_VERSION} /repo "\$@"
DOCKERWRAP
        chmod +x "${INSTALL_BIN_DIR}/docker-gitversion" 2> /dev/null || true
    fi
    if command -v docker-gitversion > /dev/null 2>&1; then
        backend="docker"
        zz_log s "Using docker-gitversion"
    else
        zz_log w "Docker is available but docker-gitversion could not be installed to {U $INSTALL_BIN_DIR}"
    fi
fi

if [ -z "$backend" ] && command -v dotnet > /dev/null 2>&1; then
    if ! command -v dotnet-gitversion > /dev/null 2>&1; then
        zz_log i "Installing GitVersion.Tool ${GITVERSION_VERSION} via dotnet..."
        dotnet tool install GitVersion.Tool --version "${GITVERSION_VERSION}" --tool-path "${INSTALL_BIN_DIR}" > /dev/null 2>&1 || true
    fi
    if command -v dotnet-gitversion > /dev/null 2>&1; then
        backend="dotnet"
        zz_log s "Using dotnet-gitversion"
    else
        zz_log w "dotnet is available but GitVersion.Tool could not be installed to {U $INSTALL_BIN_DIR}"
    fi
fi

case "$backend" in
docker)
    exec docker-gitversion -config ".gitversion" "$@"
    ;;
dotnet)
    exec dotnet-gitversion "$(git rev-parse --show-toplevel)" -config ".gitversion" "$@"
    ;;
*)
    zz_log e "Could not run GitVersion via Docker or dotnet -- neither backend is available/installable (docker-gitversion, dotnet-gitversion)"
    exit 1
    ;;
esac
