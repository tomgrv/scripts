#!/bin/sh
# Installs GitVersion.Tool via dotnet, gv's "dotnet" backend -- only when
# dotnet itself is available. Exits non-zero without side effects
# otherwise, so gv's caller can fall through to the next backend (or fail
# loudly if this was the last one).

set -eu

GITVERSION_VERSION="${GITVERSION_VERSION:-6.5.1}"
INSTALL_BIN_DIR="${INSTALL_BIN_DIR:-/usr/local/bin}"

command -v dotnet > /dev/null 2>&1 || exit 1

zz_log i "Installing GitVersion.Tool ${GITVERSION_VERSION} via dotnet..."
dotnet tool install GitVersion.Tool --version "${GITVERSION_VERSION}" --tool-path "${INSTALL_BIN_DIR}"
