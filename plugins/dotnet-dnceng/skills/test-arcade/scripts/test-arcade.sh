#!/usr/bin/env bash
# test-arcade.sh — thin wrapper that forwards to Test-Arcade.ps1
#
# This script is maintained for backward compatibility. The primary
# implementation is in Test-Arcade.ps1 (requires PowerShell 7+).
#
# Usage:
#   ./test-arcade.sh --arcade /path/to/arcade --test-repo /path/to/test-repo [options]
#
# All arguments are forwarded to Test-Arcade.ps1 with parameter name mapping:
#   --arcade       → -Arcade
#   --test-repo    → -TestRepo
#   --clean-feed   → -CleanFeed
#   --signcheck    → -SignCheck
#   --signcheck-dir→ -SignCheckDir
#   --skip-arcade-build → -SkipArcadeBuild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Map bash-style --flags to PowerShell -Flags
PWSH_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --arcade)          PWSH_ARGS+=('-Arcade' "$2");       shift 2 ;;
        --test-repo)       PWSH_ARGS+=('-TestRepo' "$2");     shift 2 ;;
        --clean-feed)      PWSH_ARGS+=('-CleanFeed');          shift   ;;
        --signcheck)       PWSH_ARGS+=('-SignCheck');           shift   ;;
        --signcheck-dir)   PWSH_ARGS+=('-SignCheckDir' "$2");  shift 2 ;;
        --skip-arcade-build) PWSH_ARGS+=('-SkipArcadeBuild');  shift   ;;
        -h|--help)
            pwsh -NoProfile -File "$SCRIPT_DIR/Test-Arcade.ps1" -?
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

exec pwsh -NoProfile -File "$SCRIPT_DIR/Test-Arcade.ps1" "${PWSH_ARGS[@]}"
