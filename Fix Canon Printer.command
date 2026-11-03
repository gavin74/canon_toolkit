#!/bin/bash
#
# Fix Canon Printer.command
#
# Double-click this file. It checks for a newer version of itself, then asks what
# you want to do. Nothing is changed without you choosing.
#
# Put it on the Desktop:
#   curl -fsSL "https://raw.githubusercontent.com/gavin74/canon_toolkit/main/Fix%20Canon%20Printer.command" \
#     -o "$HOME/Desktop/Fix Printer.command" && chmod +x "$HOME/Desktop/Fix Printer.command"
#
# If macOS refuses to run it: right-click -> Open, once.
#
set -u

VERSION="2026-11-03"

URL="https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip"
TMP=$(mktemp -d)
SPINNER_STOP="/tmp/.canon-dl.$$"

# Work out a version for a given copy of this script. Prefers the explicit
# VERSION line; falls back to a short content hash so it is never blank.
self_version() {
    local v
    v=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$1" 2>/dev/null | head -n 1)
    if [ -n "$v" ]; then
        printf '%s' "$v"
    else
        shasum -a 256 "$1" 2>/dev/null | cut -c1-7
    fi
}

# Interrupted mid-download: release the ticker so it cannot outlive the script.
trap 'touch "$SPINNER_STOP" 2>/dev/null' EXIT INT TERM

echo "=============================================="
echo "  Canon MF642Cdw - printer repair   (v$VERSION)"
echo "=============================================="

# --- fetch the latest scripts BEFORE asking anything ------------------------
echo
printf 'Checking for updates.'
rm -f "$SPINNER_STOP" 2>/dev/null
( while [ ! -f "$SPINNER_STOP" ]; do sleep 0.4; printf '.' >&2; done ) &
TICKER=$!
curl -fsSLo "$TMP/canon.zip" "$URL"
CURL_RC=$?
touch "$SPINNER_STOP" 2>/dev/null
wait "$TICKER" 2>/dev/null
rm -f "$SPINNER_STOP" 2>/dev/null
printf ' done\n'

if [ "$CURL_RC" -ne 0 ]; then
    echo
    echo "Could not download the latest version. Is this Mac online?"
    echo "Nothing has been changed."
    read -r -p "Press Return to close..." _
    exit 1
fi

if ! unzip -oq "$TMP/canon.zip" -d "$TMP"; then
    echo
    echo "Could not unzip the download. Nothing has been changed."
    read -r -p "Press Return to close..." _
    exit 1
fi

BASE=$(find "$TMP" -maxdepth 1 -type d -name 'canon_toolkit-*' 2>/dev/null | head -n 1)

if [ -z "$BASE" ] || [ ! -f "$BASE/canon-healthcheck.sh" ] || [ ! -f "$BASE/setup_canon_mf642.sh" ]; then
    echo
    echo "The download did not contain what was expected."
    echo "Nothing has been changed."
    read -r -p "Press Return to close..." _
    exit 1
fi

# --- update this button if a newer one exists ------------------------------
NEW_SELF="$BASE/Fix Canon Printer.command"
if [ "${CANON_UPDATED:-0}" != "1" ] && [ -f "$NEW_SELF" ]; then
    if ! cmp -s "$NEW_SELF" "$0"; then
        OLD_VERSION=$(self_version "$0")
        NEW_VERSION=$(self_version "$NEW_SELF")
        echo
        echo "A newer version of this tool is available."
        if [ -n "$OLD_VERSION" ]; then
            echo "   Updating from v$OLD_VERSION to v$NEW_VERSION"
        else
            echo "   Updating to v$NEW_VERSION"
        fi
        if cp "$NEW_SELF" "$0" 2>/dev/null && chmod +x "$0" 2>/dev/null; then
            echo "Restarting with the new version..."
            export CANON_UPDATED=1
            exec bash "$0"
        else
            echo "Could not update this file, so continuing with v$OLD_VERSION."
            echo "It still works; only the menu may be out of date."
        fi
    fi
fi

# --- show what is set up, then ask ----------------------------------------
echo
echo "Set up on this Mac right now:"
if lpstat -v 2>/dev/null | grep -q .; then
    lpstat -v 2>/dev/null | sed 's/^/   /'
else
    echo "   (no printers)"
fi
echo

echo "What would you like to do?"
echo
echo "  1) Check and fix        repair it if anything is wrong   (recommended)"
echo "  2) Wipe and reinstall   delete this printer's queues, then set it up again"
echo "  3) Check only           tell me what is wrong, change nothing"
echo "  4) Full diagnostic      save a detailed report to the Desktop"
echo
read -r -p "Choose 1, 2, 3 or 4 [1]: " CHOICE
[ -z "$CHOICE" ] && CHOICE=1

case "$CHOICE" in
    1|2|3|4) ;;
    *)
        echo
        echo "That isn't 1, 2, 3 or 4 - nothing has been changed."
        read -r -p "Press Return to close..." _
        exit 1
        ;;
esac

case "$CHOICE" in
    1)
        echo
        echo "Checking, and repairing anything that is wrong..."
        bash "$BASE/canon-healthcheck.sh"
        status=$?
        ;;
    2)
        echo
        echo "Removing this printer's queues and installing it again from scratch..."
        bash "$BASE/setup_canon_mf642.sh" --force
        status=$?
        ;;
    3)
        echo
        echo "Checking only - nothing will be changed..."
        bash "$BASE/canon-healthcheck.sh" --check-only
        status=$?
        ;;
    4)
        echo
        echo "Collecting a full diagnostic - nothing will be changed..."
        bash "$BASE/canon-healthcheck.sh" --debug
        status=$?
        ;;
esac

echo
if [ $status -eq 0 ]; then
    echo "Done."
else
    echo "Finished with a problem (exit $status). Scroll up for the details."
fi

read -r -p "Press Return to close..." _
exit $status
