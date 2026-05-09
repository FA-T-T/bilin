#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.2.1}"
PACKAGE_NAME="bilin-v${VERSION}-source"
RELEASE_DIR="${ROOT_DIR}/release"
STAGING_ROOT="${RELEASE_DIR}/.staging"
STAGING_DIR="${STAGING_ROOT}/${PACKAGE_NAME}"

rm -rf "${STAGING_ROOT}"
mkdir -p "${STAGING_DIR}" "${RELEASE_DIR}"

rsync -a "${ROOT_DIR}/" "${STAGING_DIR}/" \
  --exclude ".git/" \
  --exclude ".DS_Store" \
  --exclude ".env" \
  --exclude ".env.*" \
  --exclude ".venv/" \
  --exclude "__pycache__/" \
  --exclude "*.pyc" \
  --exclude ".pytest_cache/" \
  --exclude ".ruff_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".pyright/" \
  --exclude "*.tsbuildinfo" \
  --exclude "node_modules/" \
  --exclude "dist/" \
  --exclude "build/" \
  --exclude "coverage/" \
  --exclude "playwright-report/" \
  --exclude "test-results/" \
  --exclude "*.sqlite" \
  --exclude "*.sqlite-shm" \
  --exclude "*.sqlite-wal" \
  --exclude "*.db" \
  --exclude "*.db-shm" \
  --exclude "*.db-wal" \
  --exclude "libraries/" \
  --exclude "papers/" \
  --exclude "local-data/" \
  --exclude "tmp/" \
  --exclude "marketing/" \
  --exclude ".bilin/" \
  --exclude ".bilin-test/" \
  --exclude "release/"

find "${STAGING_DIR}" -name ".DS_Store" -delete
find "${STAGING_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} +

TAR_PATH="${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz"
ZIP_PATH="${RELEASE_DIR}/${PACKAGE_NAME}.zip"
rm -f "${TAR_PATH}" "${ZIP_PATH}" "${TAR_PATH}.sha256" "${ZIP_PATH}.sha256"

(
  cd "${STAGING_ROOT}"
  tar -czf "${TAR_PATH}" "${PACKAGE_NAME}"
  zip -qr "${ZIP_PATH}" "${PACKAGE_NAME}"
)

shasum -a 256 "${TAR_PATH}" > "${TAR_PATH}.sha256"
shasum -a 256 "${ZIP_PATH}" > "${ZIP_PATH}.sha256"

rm -rf "${STAGING_ROOT}"

echo "Created ${TAR_PATH}"
echo "Created ${ZIP_PATH}"
echo "Created ${TAR_PATH}.sha256"
echo "Created ${ZIP_PATH}.sha256"
