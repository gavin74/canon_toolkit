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

PRINTER_IP=$(lpinfo -v 2>/dev/null | grep -i "MF642" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
[ -z "$PRINTER_IP" ] && [ -f "$IP_FILE" ] && PRINTER_IP=$(cat "$IP_FILE")
[ -z "$PRINTER_IP" ] && read -p "Printer IP address: " PRINTER_IP

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

EXISTING=$(lpstat -p 2>/dev/null | grep -i -E "canon|mf642" | awk '{print $2}')
for q in $EXISTING; do
    sudo lpadmin -x "$q" 2>/dev/null
done

echo "📡 Building LPD queue to $PRINTER_IP"
sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -P "$PPD_PATH" -D "Canon MF642Cdw (UFR II)" -E
sudo lpadmin -p "$QUEUE" -o CNColorMode=Color -o CNTonerSave=False -o PageSize=Letter -o Resolution=600dpi
sudo lpoptions -d "$QUEUE"
sudo killall -HUP cupsd

echo "✅ Done - '$QUEUE' is now the default printer."
