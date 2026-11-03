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
# Address resolution order:
#   1. an address passed as $1
#   2. lpinfo auto-discovery
#   3. .canon_ip (the address this script found last time)
#   4. the host an existing queue already points at, if it still answers
#   5. ARP table, then a full subnet sweep (set SKIP_SCAN=1 to disable)
#   6. interactive prompt
#
set -u

QUEUE="Canon_MF642Cdw_UFRII"
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
IP_FILE="$SELF_DIR/.canon_ip"
CASK="canon-ufrii-driver"

# --- progress dots, so a slow step does not look like a hang -----------------
SPINNER_PID=""
SPINNER_STOP="/tmp/.canon-spin.$$"

# Print the label plus one dot immediately, then tick every 0.4s. The loop
# exits via a sentinel file that only appears in stop_dots, so it can never be
# "Terminated" and always shows at least one dot.
# Progress always goes to stderr, so it shows on screen but is never captured
# by command substitutions such as $(find_printer).
start_dots() {
    printf '%s.' "$1" >&2
    rm -f "$SPINNER_STOP" 2>/dev/null
    ( while [ ! -f "$SPINNER_STOP" ]; do sleep 0.4; printf '.' >&2; done ) &
    SPINNER_PID=$!
}

stop_dots() {
    touch "$SPINNER_STOP" 2>/dev/null
    [ -n "$SPINNER_PID" ] && wait "$SPINNER_PID" 2>/dev/null
    rm -f "$SPINNER_STOP" 2>/dev/null
    SPINNER_PID=""
    printf ' done\n' >&2
}

# Interrupted mid-step: release the spinner so it cannot outlive the script.
cleanup_spinner() {
    touch "${SPINNER_STOP:-/nonexistent}" 2>/dev/null
}
trap cleanup_spinner EXIT INT TERM

sweep_for_printer() {
    local subnets found s i candidates

    subnets=$(ifconfig 2>/dev/null \
        | awk '/inet / && $2 != "127.0.0.1" {print $2}' \
        | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/\1/' | sort -u)
    [ -z "$subnets" ] && return 1

    # Stage 1: anything already in the ARP table is alive, so a refused
    # connection comes back immediately. Usually finds the printer in <1s.
    candidates=$(arp -an 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p')
    if [ -n "$candidates" ]; then
        start_dots "Checking hosts this Mac already knows"
        for s in $candidates; do
            if nc -z -w 1 "$s" 9100 2>/dev/null; then
                stop_dots
                printf '%s' "$s"
                return 0
            fi
        done
        stop_dots
    fi

    # Stage 2: full sweep. Slow; only reached on a cold network.
    start_dots "Sweeping the local network (this can take a minute)"
    found=$(mktemp)

    for s in $subnets; do
        for i in {1..254}; do
            ( nc -z -w 1 "$s.$i" 9100 2>/dev/null && echo "$s.$i" >> "$found" ) &
        done
    done
    wait

    head -n 1 "$found" 2>/dev/null
    stop_dots
    rm -f "$found"
}

# --- arguments (used by the desktop menu; users do not need these) -----------
#   --force      ignore the cached address and rebuild from scratch
#   --skip-scan  never scan the network
FORCE=0
PRINTER_IP=""
for arg in "$@"; do
    case "$arg" in
        --force)      FORCE=1 ;;
        --skip-scan)  SKIP_SCAN=1 ;;
        [0-9]*.[0-9]*.[0-9]*.[0-9]*) PRINTER_IP="$arg" ;;
        *) echo "Ignoring unknown argument: $arg" >&2 ;;
    esac
done

if [ -z "$PRINTER_IP" ]; then
    start_dots "Asking macOS where the printer is"
    PRINTER_IP=$(lpinfo -v 2>/dev/null | grep -i "MF64" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    stop_dots
fi

# Reuse the cached address, but only if it still answers. A stale cache must
# never silently point the new queue at a dead printer.
if [ -z "$PRINTER_IP" ] && [ "$FORCE" -eq 0 ] && [ -f "$IP_FILE" ]; then
    cached=$(cat "$IP_FILE")
    if [ -n "$cached" ] && nc -z -w 2 "$cached" 9100 2>/dev/null; then
        PRINTER_IP="$cached"
    fi
fi

# Reuse the address an existing queue already points at, if it still answers.
# This is a live check, not a cached assumption, so it is safe even with --force -
# and it avoids a slow sweep in the common case.
if [ -z "$PRINTER_IP" ]; then
    queued=$(lpstat -v 2>/dev/null | sed -n "s/^device for ${QUEUE}: //p")
    if [ -n "$queued" ]; then
        qh=$(printf '%s' "$queued" | sed -E 's#^[A-Za-z]+://##; s#/.*$##; s#:[0-9]+$##')
        case "$qh" in
            ''|*[!0-9.]*) : ;;
            *) nc -z -w 2 "$qh" 9100 2>/dev/null && PRINTER_IP="$qh" ;;
        esac
    fi
fi

# Last resort: find it on the wire.
if [ -z "$PRINTER_IP" ] && [ "${SKIP_SCAN:-0}" != "1" ]; then
    PRINTER_IP=$(sweep_for_printer)
fi

# Only ask if everything above came up empty.
if [ -z "$PRINTER_IP" ]; then
    read -p "Printer IP address: " PRINTER_IP
fi

if [ -z "$PRINTER_IP" ]; then
    echo "❌ No printer address given."
    exit 1
fi

# Never tear down a working queue for a printer we cannot actually reach.
if ! nc -z -w 3 "$PRINTER_IP" 9100 2>/dev/null; then
    echo
    echo "⚠️  Nothing answers at $PRINTER_IP on port 9100."
    echo "   The printer may be asleep, switched off, or at a different address."
    echo "   No existing queues will be touched unless you continue."
    echo
    read -p "Continue anyway and replace the existing queues? (y/N): " PROCEED
    case "${PROCEED:-}" in
        [Yy]*) ;;
        *) echo "Stopped. Nothing was changed."; exit 1 ;;
    esac
fi

# ---------------------------------------------------------------------------
# Find the Canon driver the way CUPS itself sees it. Matching on a PPD filename
# is unreliable: the file may be gzipped or generically named.
# ---------------------------------------------------------------------------
find_model() { lpinfo -m 2>/dev/null | awk '{print $1}' | grep -iE 'mf64[0-9]' | head -n 1; }
find_ppd()   { find /Library/Printers/PPDs/Contents/Resources -type f -iname '*MF64*' -print -quit 2>/dev/null; }

start_dots "Looking for the Canon driver"
DRIVER_MODEL=$(find_model)
DRIVER_PPD=""
[ -z "$DRIVER_MODEL" ] && DRIVER_PPD=$(find_ppd)
stop_dots

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
start_dots "Checking what is set up already"
EXISTING=$(lpstat -v 2>/dev/null | grep -E "${PRINTER_IP//./\\.}|MF64|Canon" | sed -E 's/^device for ([^:]+):.*/\1/')
stop_dots

if [ -n "$EXISTING" ]; then
    echo "Existing queue(s) to replace:"
    printf '%s\n' "$EXISTING" | sed 's/^/   - /'
    start_dots "Removing them"
    printf '%s\n' "$EXISTING" | while IFS= read -r q; do
        [ -z "$q" ] && continue
        sudo lpadmin -x "$q" 2>/dev/null
    done
    stop_dots
fi

start_dots "Building the new queue for $PRINTER_IP"
if [ -n "$DRIVER_MODEL" ]; then
    sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -m "$DRIVER_MODEL" \
        -D "Canon MF642Cdw (UFR II)" -o printer-is-shared=false -E >/dev/null 2>&1
    build_status=$?
else
    sudo lpadmin -p "$QUEUE" -v "lpd://$PRINTER_IP" -P "$DRIVER_PPD" \
        -D "Canon MF642Cdw (UFR II)" -o printer-is-shared=false -E >/dev/null 2>&1
    build_status=$?
fi
sudo lpadmin -p "$QUEUE" -o CNColorMode=Color -o CNTonerSave=False -o PageSize=Letter -o Resolution=600dpi >/dev/null 2>&1
sudo lpoptions -d "$QUEUE" >/dev/null 2>&1
stop_dots

if [ "$build_status" -ne 0 ]; then
    echo "❌ Could not create the print queue (lpadmin failed)."
    echo "   Nothing else was changed. Try: sudo lpadmin -p $QUEUE -v lpd://$PRINTER_IP -m \"$DRIVER_LABEL\" -E"
    exit 1
fi

start_dots "Restarting the print system"
sudo killall -HUP cupsd 2>/dev/null
sleep 1
stop_dots

# Prove which driver the queue actually ended up with. If this says AirPrint,
# the queue is still doomed to Error 853.
echo "   Driver: $DRIVER_LABEL"
if sudo lpstat -l -p "$QUEUE" 2>/dev/null | grep -qi airprint; then
    echo "⚠️  This queue still reports AirPrint - the Canon driver did not take."
    exit 1
fi

echo "✅ Done - '$QUEUE' is now the default printer."

# Configuration being correct is not the same as a page coming out. Ask, and
# then actually watch the job through the queue.
echo
read -p "Print a test page now, to check it really works? (Y/n): " TESTPAGE

case "${TESTPAGE:-Y}" in
    [Nn]*)
        echo "Skipped. If printing still fails, run the button and choose 4."
        ;;
    *)
        TMPPAGE=$(mktemp /tmp/canon-test.XXXXXX.pdf) || TMPPAGE=""
        if [ -z "$TMPPAGE" ]; then
            echo "Could not create a temporary file for the test page."
            exit 1
        fi

        # A colour page with swatches and a gradation ramp tells you far more
        # than a page of black text. Falls back to text if the helper is absent.
        if [ -f "$SELF_DIR/canon-testpage.sh" ]; then
            bash "$SELF_DIR/canon-testpage.sh" "$TMPPAGE" \
                "$QUEUE" "$DRIVER_LABEL" "$PRINTER_IP" >/dev/null 2>&1
        fi

        if [ ! -s "$TMPPAGE" ]; then
            {
                echo "Canon MF642Cdw test page"
                echo
                echo "If you can read this, printing works."
                echo
                echo "Date   : $(date)"
                echo "Queue  : $QUEUE"
                echo "Driver : $DRIVER_LABEL"
                echo "Printer: $PRINTER_IP"
            } > "$TMPPAGE"
        fi

        start_dots "Sending a test page"
        lpr -P "$QUEUE" "$TMPPAGE" 2>/dev/null
        lpr_status=$?
        stop_dots

        if [ "$lpr_status" -ne 0 ]; then
            echo "❌ Could not submit the job - lpr failed (exit $lpr_status)."
            rm -f "$TMPPAGE"
            exit 1
        fi

        start_dots "Waiting for the printer to take it"
        waited=0
        while [ "$waited" -lt 45 ]; do
            job=$(lpstat -o "$QUEUE" 2>/dev/null)
            [ -z "$job" ] && break
            sleep 1
            waited=$((waited + 1))
        done
        stop_dots
        rm -f "$TMPPAGE"

        if [ -z "$(lpstat -o "$QUEUE" 2>/dev/null)" ]; then
            echo "✅ The job was accepted and left the queue - a page should be printing."
            echo "   If nothing comes out, the problem is the printer, not the Mac."
        else
            echo "⚠️  The job is still sitting in the queue after 45 seconds."
            echo "   That means it was accepted but not printed - usually the printer"
            echo "   being offline, or a driver problem."
            echo
            echo "   Check the printer's screen, then run the button and choose 4 for a"
            echo "   full diagnostic written to your Desktop."
            exit 1
        fi
        ;;
esac
