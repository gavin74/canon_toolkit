#!/bin/bash
#
# Double-click this file in Finder to install the Canon MF642Cdw print queue.
#
# macOS opens Terminal and runs setup_canon_mf642.sh, which:
#   - finds the printer on the network (no IP needed)
#   - offers to install the Canon driver via Homebrew if it's missing
#   - removes any AirPrint queue and rebuilds it over LPD with UFR II
#
# If macOS refuses to run it ("cannot be opened because it is from an
# unidentified developer"), right-click it and choose Open once, or run:
#   xattr -d com.apple.quarantine "Install Canon Printer.command"
#
cd "$(dirname "$0")" || exit 1

echo
echo "=== Canon MF642Cdw setup ==="
echo

bash ./setup_canon_mf642.sh "$@"
status=$?

echo
if [ $status -eq 0 ]; then
    echo "Finished. You can close this window."
else
    echo "Stopped with an error (exit $status). Scroll up for the reason."
fi

# Keep the window open so the output is readable when launched from Finder.
read -r -p "Press Return to close..." _
exit $status
