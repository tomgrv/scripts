#!/bin/sh
# Installs the docker-gitversion wrapper, gv's "docker" backend -- only
# when Docker is actually usable. `docker info` (not just `command -v
# docker`) confirms a daemon is reachable: the CLI can be on PATH with no
# daemon behind it (e.g. no docker-in-docker in this container), which
# would otherwise hang or fail on the first real `docker run`. Exits
# non-zero without side effects when Docker isn't usable, so gv's caller
# can fall through to the next backend.

set -eu

GITVERSION_VERSION="${GITVERSION_VERSION:-6.5.1}"
INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"

command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1 || exit 1

zz_log i "Installing docker-gitversion wrapper (gittools/gitversion:${GITVERSION_VERSION})..."
cat > "${INSTALL_BIN_DIR}/docker-gitversion" << DOCKERWRAP
#!/bin/sh
cd "\$(git rev-parse --show-toplevel)" && \\
docker run --rm -v "\$(git rev-parse --show-toplevel):/repo" gittools/gitversion:${GITVERSION_VERSION} /repo "\$@"
DOCKERWRAP
chmod +x "${INSTALL_BIN_DIR}/docker-gitversion"
