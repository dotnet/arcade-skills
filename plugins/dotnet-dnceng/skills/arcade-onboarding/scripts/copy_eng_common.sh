#!/usr/bin/env bash
# Copy eng/common from dotnet/arcade into the target repository.
# Usage: copy_eng_common.sh [target_repo_root] [arcade_ref]
#   target_repo_root: Git repository root being onboarded (default: current directory)
#   arcade_ref: Arcade branch or tag (default: main)

set -euo pipefail

TARGET_ROOT="${1:-.}"
ARCADE_REF="${2:-main}"
TEMP_DIR=""
STAGED_COMMON=""
BACKUP_COMMON=""
TARGET_ENG=""
NEW_COMMON_INSTALLED=0
INSTALL_COMMITTED=0

cleanup() {
  if [ -n "$STAGED_COMMON" ] && [ -d "$STAGED_COMMON" ]; then
    rm -rf -- "$STAGED_COMMON"
  fi

  if [ "$NEW_COMMON_INSTALLED" -eq 1 ] && [ "$INSTALL_COMMITTED" -eq 0 ] && [ -e "$TARGET_ENG/common" ]; then
    rm -rf -- "$TARGET_ENG/common"
  fi

  if [ -n "$BACKUP_COMMON" ] && [ -e "$BACKUP_COMMON" ]; then
    mv -- "$BACKUP_COMMON" "$TARGET_ENG/common"
  fi

  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [[ "$TARGET_ROOT" == -* ]]; then
  echo "ERROR: target repository path must not start with '-': $TARGET_ROOT" >&2
  exit 1
fi

if [ ! -d "$TARGET_ROOT" ]; then
  echo "ERROR: target repository does not exist: $TARGET_ROOT" >&2
  exit 1
fi

TARGET_ROOT=$(cd -- "$TARGET_ROOT" && pwd -P)
GIT_ROOT=$(git -C "$TARGET_ROOT" rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$GIT_ROOT" ]; then
  echo "ERROR: target must be a Git repository root: $TARGET_ROOT" >&2
  exit 1
fi

GIT_ROOT=$(cd -- "$GIT_ROOT" && pwd -P)
if [ "$TARGET_ROOT" != "$GIT_ROOT" ]; then
  echo "ERROR: target must be the repository root: $GIT_ROOT" >&2
  exit 1
fi

if [[ "$ARCADE_REF" == -* ]]; then
  echo "ERROR: Arcade ref must not start with '-': $ARCADE_REF" >&2
  exit 1
fi

TARGET_ENG="$TARGET_ROOT/eng"
if [ -L "$TARGET_ENG" ] || [ -L "$TARGET_ENG/common" ]; then
  echo "ERROR: eng and eng/common must not be symbolic links" >&2
  exit 1
fi

if [ -n "$(git -C "$TARGET_ROOT" status --porcelain --untracked-files=all -- eng/common)" ]; then
  echo "ERROR: eng/common has uncommitted changes; commit or stash them before replacing it" >&2
  exit 1
fi

TEMP_DIR=$(mktemp -d)

echo "==> Cloning dotnet/arcade@${ARCADE_REF} (shallow)..."
git clone --depth 1 --filter=blob:none --sparse --branch "$ARCADE_REF" --single-branch \
  https://github.com/dotnet/arcade.git "$TEMP_DIR/arcade" 2>&1
git -C "$TEMP_DIR/arcade" sparse-checkout set eng/common

if [ ! -d "$TEMP_DIR/arcade/eng/common" ]; then
  echo "ERROR: eng/common not found in arcade clone" >&2
  exit 1
fi

mkdir -p "$TARGET_ENG"

STAGED_COMMON=$(mktemp -d "$TARGET_ENG/.common.new.XXXXXX")
cp -R "$TEMP_DIR/arcade/eng/common/." "$STAGED_COMMON/"

if [ -e "$TARGET_ENG/common" ]; then
  BACKUP_COMMON="$TARGET_ENG/.common.backup.$$"
  if [ -e "$BACKUP_COMMON" ]; then
    echo "ERROR: backup path already exists: $BACKUP_COMMON" >&2
    exit 1
  fi

  echo "==> Staging replacement for existing eng/common/..."
  mv -- "$TARGET_ENG/common" "$BACKUP_COMMON"
fi

echo "==> Installing eng/common/ in ${TARGET_ENG}..."
mv -- "$STAGED_COMMON" "$TARGET_ENG/common"
STAGED_COMMON=""
NEW_COMMON_INSTALLED=1

echo "==> Setting executable permissions on .sh files..."
find "$TARGET_ENG/common" -name "*.sh" -exec chmod +x {} \;

if [ -n "$BACKUP_COMMON" ]; then
  rm -rf -- "$BACKUP_COMMON"
  BACKUP_COMMON=""
fi
INSTALL_COMMITTED=1

SH_COUNT=$(find "$TARGET_ENG/common" -name "*.sh" | wc -l | tr -d ' ')
TOTAL_COUNT=$(find "$TARGET_ENG/common" -type f | wc -l | tr -d ' ')

echo "==> Done! Copied ${TOTAL_COUNT} files (${SH_COUNT} shell scripts marked executable)"
echo ""
echo "IMPORTANT: From the repository root, run:"
echo "  find eng/common -name '*.sh' -exec git add --chmod=+x -- {} +"
echo "to ensure executable permissions are tracked by Git."
