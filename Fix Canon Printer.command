#!/bin/bash
#
# Fix Canon Printer.command
#
# Double-click this after the printer stops working. It downloads the latest
# setup script and re-runs it, which:
#   - finds the printer wherever it currently is (no IP needed)
#   - removes any AirPrint queue macOS created behind your back
#   - rebuilds the queue against the Canon UFR II driver
#
# Put it on the Desktop and rename it "Fix Printer" if that's friendlier.
#
# If macOS refuses to run it: right-click -> Open, once.
#
set -u

URL="https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip"
TMP=$(mktemp -d)

echo "======================================"
echo "  Canon MF642Cdw - repair"
echo "======================================"
echo

echo "Downloading the latest setup script..."
if ! curl -fsSLo "$TMP/canon.zip" "$URL"; then
    echo
    echo "❌ Download failed. Is this Mac online?"
    read -r -p "Press Return to close..." _
    exit 1
fi

if ! unzip -oq "$TMP/canon.zip" -d "$TMP"; then
    echo "❌ Could not unzip the download."
    read -r -p "Press Return to close..." _
    exit 1
fi

echo
bash "$TMP/canon_toolkit-main/setup_canon_mf642.sh" "$@"
status=$?

echo
if [ $status -eq 0 ]; then
    echo "✅ Printer repaired."
else
    echo "❌ Repair failed (exit $status)."
    echo "   Scroll up for the reason - usually the Canon driver is missing."
fi

read -r -p "Press Return to close..." _
exit $status
