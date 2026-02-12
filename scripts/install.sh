#!/usr/bin/env bash
set -euo pipefail

REPO="TheInkedEngineer/apple-notes-mcp"
BINARY="apple-notes-mcp"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "$OS" != "Darwin" ]]; then
  echo "This installer supports macOS only."
  exit 1
fi

case "$ARCH" in
  arm64)
    TARGET="darwin_arm64"
    ;;
  x86_64)
    echo "No Intel release artifact is published yet. Use source build for now."
    exit 1
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

VERSION="${1:-latest}"
if [[ "$VERSION" == "latest" ]]; then
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
  BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

ARCHIVE="${BINARY}_${TARGET}.tar.gz"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading ${ARCHIVE}..."
curl -fL "${BASE_URL}/${ARCHIVE}" -o "${TMP_DIR}/${ARCHIVE}"
curl -fL "${BASE_URL}/checksums.txt" -o "${TMP_DIR}/checksums.txt"

echo "Verifying checksum..."
(
  cd "$TMP_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c checksums.txt --ignore-missing
  else
    expected="$(awk "/${ARCHIVE}\$/ {print \$1}" checksums.txt)"
    actual="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
      echo "Checksum mismatch for ${ARCHIVE}"
      exit 1
    fi
  fi
)

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}"

mkdir -p "$INSTALL_DIR"
if [[ -w "$INSTALL_DIR" ]]; then
  install -m 0755 "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
else
  sudo install -m 0755 "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
fi

echo "Installed ${BINARY} to ${INSTALL_DIR}/${BINARY}"
