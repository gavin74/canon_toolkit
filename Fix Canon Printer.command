#!/bin/bash
#
# Fix Canon Printer.command
#
# Double-click this file. It asks what you want to do, then does exactly that.
# Nothing happens without you choosing.
#
# Put it on the Desktop:
#   curl -fsSL "https://raw.githubusercontent.com/gavin74/canon_toolkit/main/Fix%20Canon%20Printer.command" \
#     -o "$HOME/Desktop/Fix Printer.command" && chmod +x "$HOME/Desktop/Fix Printer.command"
#
# If macOS refuses to run it: right-click -> Open, once.
#
set -u

URL="https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip"
TMP=$(mktemp -d)

# Interrupted mid-download: release the ticker so it cannot outlive the script.
trap '[ -n "${SPINNER_STOP:-}" ] && touch "$SPINNER_STOP" 2>/dev/null' EXIT INT TERM

echo "=============================================="
echo "  Canon MF642Cdw - printer repair"
echo "=============================================="
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
echo
read -r -p "Choose 1, 2 or 3 [1]: " CHOICE
[ -z "$CHOICE" ] && CHOICE=1

case "$CHOICE" in
    1|2|3) ;;
    *)
        echo
        echo "That isn't 1, 2 or 3 - nothing has been changed."
        read -r -p "Press Return to close..." _
        exit 1
        ;;
esac

echo
# Label + one dot immediately, then tick until the download finishes.
printf 'Downloading the latest scripts.'
SPINNER_STOP="/tmp/.canon-dl.$$"
rm -f "$SPINNER_STOP" 2>/dev/null
( while [ ! -f "$SPINNER_STOP" ]; do sleep 0.4; printf '.'; done ) &
CURL_TICKER=$!
curl -fsSLo "$TMP/canon.zip" "$URL"
CURL_RC=$?
touch "$SPINNER_STOP" 2>/dev/null
wait "$CURL_TICKER" 2>/dev/null
rm -f "$SPINNER_STOP" 2>/dev/null
printf ' done\n'

if [ "$CURL_RC" -ne 0 ]; then
    echo "Download failed. Is this Mac online?"
    read -r -p "Press Return to close..." _
    exit 1
fi

if ! unzip -oq "$TMP/canon.zip" -d "$TMP"; then
    echo
    echo "Could not unzip the download."
    read -r -p "Press Return to close..." _
    exit 1
fi

BASE=$(find "$TMP" -maxdepth 1 -type d -name 'canon_toolkit-*' 2>/dev/null | head -n 1)

if [ -z "$BASE" ] || [ ! -f "$BASE/canon-healthcheck.sh" ]; then
    echo
    echo "The download did not contain what was expected."
    echo "Nothing has been changed."
    read -r -p "Press Return to close..." _
    exit 1
fi

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
esac

echo
if [ $status -eq 0 ]; then
    echo "Done."
else
    echo "Finished with a problem (exit $status). Scroll up for the details."
fi

read -r -p "Press Return to close..." _
exit $status
