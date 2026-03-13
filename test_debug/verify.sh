#!/usr/bin/env bash
# verify.sh -- Run luacheck static analysis and busted unit tests
# for the wezterm-resurrect plugin.
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
#
# Usage:
#   bash test_debug/verify.sh          # Run from repo root
#   bash test_debug/verify.sh --lint   # Luacheck only
#   bash test_debug/verify.sh --test   # Busted tests only

set -uo pipefail

# ---------------------------------------------------------------------------
# Paths (portable: works from repo root on Windows Git Bash / MSYS2)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

LUACHECK="$TOOLS_DIR/luacheck.exe"
LUA54="$TOOLS_DIR/lua54.exe"

# Luarocks systree where busted and its dependencies live
SYSTREE="C:/ProgramData/chocolatey/lib/luarocks/luarocks-2.4.4-win32/systree"
BUSTED_SCRIPT="$SYSTREE/lib/luarocks/rocks/busted/2.3.0-1/bin/busted"

# ---------------------------------------------------------------------------
# Mode selection
# ---------------------------------------------------------------------------
RUN_LINT=true
RUN_TEST=true

if [[ "${1:-}" == "--lint" ]]; then
    RUN_LINT=true
    RUN_TEST=false
elif [[ "${1:-}" == "--test" ]]; then
    RUN_LINT=false
    RUN_TEST=true
fi

FAILURES=0

# ---------------------------------------------------------------------------
# Luacheck: static analysis
# ---------------------------------------------------------------------------
if $RUN_LINT; then
    echo "========================================"
    echo "  LUACHECK -- Static Analysis"
    echo "========================================"

    if [[ ! -f "$LUACHECK" ]]; then
        echo "SKIP: luacheck not found at $LUACHECK"
        FAILURES=$((FAILURES + 1))
    else
        cd "$REPO_ROOT"

        # Collect .lua files using relative paths (luacheck on Windows
        # has issues with absolute config paths, so we run from repo root)
        LUA_FILES=()
        while IFS= read -r -d '' f; do
            LUA_FILES+=("$f")
        done < <(find plugin -name '*.lua' -print0 2>/dev/null)

        if [[ ${#LUA_FILES[@]} -eq 0 ]]; then
            echo "WARN: No .lua files found under plugin/"
        else
            echo "Checking ${#LUA_FILES[@]} Lua files..."
            echo ""
            "$LUACHECK" --config .luacheckrc "${LUA_FILES[@]}"
            LUACHECK_EXIT=$?

            echo ""
            # luacheck exit codes: 0=clean, 1=warnings only, 2=errors
            if [[ $LUACHECK_EXIT -eq 0 ]]; then
                echo "LUACHECK: PASSED (no warnings)"
            elif [[ $LUACHECK_EXIT -eq 1 ]]; then
                echo "LUACHECK: PASSED (warnings only -- no errors)"
            else
                echo "LUACHECK: FAILED (errors found)"
                FAILURES=$((FAILURES + 1))
            fi
        fi
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# Busted: unit tests
# ---------------------------------------------------------------------------
if $RUN_TEST; then
    echo "========================================"
    echo "  BUSTED -- Unit Tests"
    echo "========================================"

    cd "$REPO_ROOT"

    # Locate spec files
    SPEC_DIR="$REPO_ROOT/plugin/resurrect/spec"
    SPEC_COUNT=$(find "$SPEC_DIR" -name '*_spec.lua' 2>/dev/null | wc -l)

    if [[ "$SPEC_COUNT" -eq 0 ]]; then
        echo "SKIP: No spec files found in $SPEC_DIR"
    elif [[ ! -f "$LUA54" ]]; then
        echo "SKIP: lua54 not found at $LUA54"
        FAILURES=$((FAILURES + 1))
    elif [[ ! -f "$BUSTED_SCRIPT" ]]; then
        echo "SKIP: busted not found at $BUSTED_SCRIPT"
        FAILURES=$((FAILURES + 1))
    else
        echo "Running $SPEC_COUNT spec file(s)..."
        echo ""

        export LUA_PATH="$SYSTREE/share/lua/5.1/?.lua;$SYSTREE/share/lua/5.1/?/init.lua;;"

        # Pass relative spec path -- busted resolves it from CWD
        "$LUA54" "$BUSTED_SCRIPT" -o plainTerminal "plugin\\resurrect\\spec"
        BUSTED_EXIT=$?

        echo ""
        if [[ $BUSTED_EXIT -eq 0 ]]; then
            echo "BUSTED: PASSED"
        else
            echo "BUSTED: FAILED (exit code $BUSTED_EXIT)"
            FAILURES=$((FAILURES + 1))
        fi
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================"
if [[ $FAILURES -eq 0 ]]; then
    echo "  RESULT: ALL CHECKS PASSED"
else
    echo "  RESULT: $FAILURES CHECK(S) FAILED"
fi
echo "========================================"

exit $FAILURES
