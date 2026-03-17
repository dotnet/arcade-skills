#!/usr/bin/env bash
# Copy eng/common from dotnet/arcade into the target repository.
# Usage: copy_eng_common.sh [target_repo_root] [arcade_ref]
#   target_repo_root: Path to the repository being onboarded (default: current directory)
#   arcade_ref: Git ref to use (branch/tag/SHA) (default: main)

set -euo pipefail

TARGET_ROOT="${1:-.}"
ARCADE_REF="${2:-main}"
TEMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

echo "==> Cloning dotnet/arcade@${ARCADE_REF} (shallow)..."
git clone --depth 1 --branch "$ARCADE_REF" --single-branch \
  https://github.com/dotnet/arcade.git "$TEMP_DIR/arcade" 2>&1

if [ ! -d "$TEMP_DIR/arcade/eng/common" ]; then
  echo "ERROR: eng/common not found in arcade clone" >&2
  exit 1
fi

TARGET_ENG="$TARGET_ROOT/eng"
mkdir -p "$TARGET_ENG"

if [ -d "$TARGET_ENG/common" ]; then
  echo "==> Removing existing eng/common/..."
  rm -rf "$TARGET_ENG/common"
fi

echo "==> Copying eng/common/ to ${TARGET_ENG}/common/..."
cp -r "$TEMP_DIR/arcade/eng/common" "$TARGET_ENG/common"

echo "==> Setting executable permissions on .sh files..."
find "$TARGET_ENG/common" -name "*.sh" -exec chmod +x {} \;

SH_COUNT=$(find "$TARGET_ENG/common" -name "*.sh" | wc -l | tr -d ' ')
TOTAL_COUNT=$(find "$TARGET_ENG/common" -type f | wc -l | tr -d ' ')

echo "==> Done! Copied ${TOTAL_COUNT} files (${SH_COUNT} shell scripts marked executable)"
echo ""
echo "IMPORTANT: Run 'git add --chmod=+x eng/common/**/*.sh' before committing"
echo "           to ensure executable permissions are tracked by git."
