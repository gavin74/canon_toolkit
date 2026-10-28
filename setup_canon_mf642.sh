#!/bin/bash
#
# Canon MF642Cdw - macOS setup
#
# AirPrint's driver is what triggers Error 853 (memory crash) on this printer.
# This removes any existing Canon/AirPrint queue and rebuilds it over LPD using
# the official Canon UFR II PPD.
#
# Address resolution: lpinfo auto-discovery -> .canon_ip -> interactive prompt.
#
set -u

IP_FILE="$(dirname "$0")/.canon_ip"

if [ -n "${1:-}" ]; then
    PRINTER_IP="$1"
else
    PRINTER_IP=$(lpinfo -v 2>/dev/null | grep -i "MF642" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    [ -z "$PRINTER_IP" ] && [ -f "$IP_FILE" ] && PRINTER_IP=$(cat "$IP_FILE")
    [ -z "$PRINTER_IP" ] && read -p "Printer IP address: " PRINTER_IP
fi

if [ -z "$PRINTER_IP" ]; then
    echo "❌ No printer address given."
    exit 1
fi

# Find the Canon PPD before asking for a password.
PPD_PATH=$(find /Library/Printers/PPDs/Contents/Resources -type f \( -iname "*MF640*" -o -iname "*MF642*" \) -print -quit 2>/dev/null)
if [ -z "$PPD_PATH" ]; then
    echo "❌ Canon UFR II PPD not found. Install the Canon MF642 driver package first."
    exit 1
fi

sudo -v || exit 1

QUEUE="Canon_MF642Cdw_UFRII"

# Remove every queue that points at this printer, whatever macOS named it.
# Matching on the device URI also catches AirPrint queues whose names don't
# mention Canon.
EXISTING=$(lpstat -v 2>/dev/null | grep -E "${PRINTER_IP//./\\.}|MF642|Canon" | sed -E 's/^device for ([^:]+):.*/\1/')
if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS= read -r q; do
        [ -z "$q" ] && continue
        echo "🗑  Removing existing queue: $q"
        sudo lpadmin -x "$q" 2>/dev/null
    done
fi

echo "📡 Building LPD queue to $PRINTER_IP"
sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -P "$PPD_PATH" -D "Canon MF642Cdw (UFR II)" -o printer-is-shared=false -E
sudo lpadmin -p "$QUEUE" -o CNColorMode=Color -o CNTonerSave=False -o PageSize=Letter -o Resolution=600dpi
sudo lpoptions -d "$QUEUE"
sudo killall -HUP cupsd

# Prove which driver the queue actually ended up with. If this says AirPrint,
# the PPD didn't take and the queue is still doomed to Error 853.
PPD_USED="/etc/cups/ppd/$QUEUE.ppd"
if sudo test -f "$PPD_USED"; then
    echo "   Driver: $(sudo grep -m1 '^\*NickName' "$PPD_USED" | cut -d'"' -f2)"
fi

echo "✅ Done - '$QUEUE' is now the default printer."
