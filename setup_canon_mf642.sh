#!/bin/bash
#
# Canon MF642Cdw - macOS setup
#
# macOS creates an AirPrint queue by default, even when the Canon UFR II driver
# is installed. AirPrint is what triggers Error 853 (memory crash) on this
# printer, and it also drops paper-type control, so glossy prints smear.
#
# This removes every queue pointing at the printer and rebuilds it over LPD
# bound to the Canon UFR II driver.
#
# Address resolution: lpinfo auto-discovery -> .canon_ip -> interactive prompt.
#
set -u

QUEUE="Canon_MF642Cdw_UFRII"
IP_FILE="$(dirname "$0")/.canon_ip"
CASK="canon-ufrii-driver"

if [ -n "${1:-}" ]; then
    PRINTER_IP="$1"
else
    PRINTER_IP=$(lpinfo -v 2>/dev/null | grep -i "MF64" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    [ -z "$PRINTER_IP" ] && [ -f "$IP_FILE" ] && PRINTER_IP=$(cat "$IP_FILE")
    [ -z "$PRINTER_IP" ] && read -p "Printer IP address: " PRINTER_IP
fi

if [ -z "$PRINTER_IP" ]; then
    echo "❌ No printer address given."
    exit 1
fi

# ---------------------------------------------------------------------------
# Find the Canon driver the way CUPS itself sees it. Matching on a PPD filename
# is unreliable: the file may be gzipped or generically named.
# ---------------------------------------------------------------------------
find_model() { lpinfo -m 2>/dev/null | awk '{print $1}' | grep -iE 'mf64[0-9]' | head -n 1; }
find_ppd()   { find /Library/Printers/PPDs/Contents/Resources -type f -iname '*MF64*' -print -quit 2>/dev/null; }

DRIVER_MODEL=$(find_model)
DRIVER_PPD=""
[ -z "$DRIVER_MODEL" ] && DRIVER_PPD=$(find_ppd)

if [ -z "$DRIVER_MODEL" ] && [ -z "$DRIVER_PPD" ]; then
    echo "❌ No Canon MF64x driver found on this Mac."
    echo

    if command -v brew >/dev/null 2>&1; then
        echo "   Homebrew is available and maintains this driver as a cask:"
        echo "     brew install --cask $CASK"
        read -p "   Install it now? (y/N): " INSTALL_NOW
        if [[ "${INSTALL_NOW:-}" =~ ^[Yy]$ ]]; then
            brew install --cask "$CASK" || exit 1
            DRIVER_MODEL=$(find_model)
            [ -z "$DRIVER_MODEL" ] && DRIVER_PPD=$(find_ppd)
        fi
    else
        echo "   Install Homebrew (https://brew.sh), then:"
        echo "     brew install --cask $CASK"
        echo "   Or download 'UFR II/UFRII LT Printer Driver & Utilities for Mac'"
        echo "   from Canon's MF642Cdw support page and run the installer."
    fi

    if [ -z "$DRIVER_MODEL" ] && [ -z "$DRIVER_PPD" ]; then
        echo
        echo "❌ Driver still missing - stopping before touching any print queue."
        exit 1
    fi
    echo "✅ Driver found."
    echo
fi

sudo -v || exit 1

# What the driver calls itself, for the verification line at the end.
if [ -n "$DRIVER_MODEL" ]; then
    DRIVER_LABEL="$DRIVER_MODEL"
else
    DRIVER_LABEL="$(basename "$DRIVER_PPD")"
fi

# Remove every queue pointing at this printer, whatever macOS named it.
# Matching on the device URI also catches AirPrint queues whose names don't
# mention Canon.
EXISTING=$(lpstat -v 2>/dev/null | grep -E "${PRINTER_IP//./\\.}|MF64|Canon" | sed -E 's/^device for ([^:]+):.*/\1/')
if [ -n "$EXISTING" ]; then
    echo "$EXISTING" | while IFS= read -r q; do
        [ -z "$q" ] && continue
        echo "🗑  Removing existing queue: $q"
        sudo lpadmin -x "$q" 2>/dev/null
    done
fi

echo "📡 Building LPD queue to $PRINTER_IP"
if [ -n "$DRIVER_MODEL" ]; then
    sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -m "$DRIVER_MODEL" \
        -D "Canon MF642Cdw (UFR II)" -o printer-is-shared=false -E
else
    sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -P "$DRIVER_PPD" \
        -D "Canon MF642Cdw (UFR II)" -o printer-is-shared=false -E
fi
sudo lpadmin -p "$QUEUE" -o CNColorMode=Color -o CNTonerSave=False -o PageSize=Letter -o Resolution=600dpi
sudo lpoptions -d "$QUEUE"
sudo killall -HUP cupsd

# Prove which driver the queue actually ended up with. If this says AirPrint,
# the queue is still doomed to Error 853.
echo "   Driver: $DRIVER_LABEL"
if sudo lpstat -l -p "$QUEUE" 2>/dev/null | grep -qi airprint; then
    echo "⚠️  This queue still reports AirPrint - the Canon driver did not take."
    exit 1
fi

echo "✅ Done - '$QUEUE' is now the default printer."
