#!/bin/bash
#
# canon-healthcheck.sh - is the Canon MF642Cdw print queue healthy? Fix it if not.
#
# Usage:
#   ./canon-healthcheck.sh               # check, and repair automatically
#   ./canon-healthcheck.sh --check-only  # report only, change nothing
#
# macOS only - uses lpstat/lpadmin and ifconfig.
#
# Exit codes: 0 healthy (or repaired), 1 still broken.
#
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP="$DIR/setup_canon_mf642.sh"
IP_FILE="$DIR/.canon_ip"
QUEUE="Canon_MF642Cdw_UFRII"
PORT=9100
DO_FIX=1
DEBUG=0

for arg in "$@"; do
    case "$arg" in
        --check-only) DO_FIX=0 ;;
        --debug)      DO_FIX=0; DEBUG=1 ;;
        *) : ;;
    esac
done

PROBLEMS=""
add_problem() { PROBLEMS="${PROBLEMS}${1}
"; }

say() { printf '%s\n' "$*"; }

# lpd://192.168.50.174  /  lpd://192.168.50.174/  /  ipp://host:631/ipp/print
# Compare hosts, not raw strings - CUPS normalises URIs.
uri_host() {
    printf '%s' "$1" | sed -E 's#^[A-Za-z]+://##; s#/.*$##; s#:[0-9]+$##'
}

# ---------------------------------------------------------------------------
# Find the printer: lpinfo, then the cached address, then sweep the subnets.
# A cached address is only trusted if it actually answers.
# ---------------------------------------------------------------------------
find_printer() {
    local ip subnets found s i queued qh

    # If an existing queue already points somewhere that answers, trust it.
    # This avoids sweeping (and waking the printer) on an otherwise healthy Mac.
    queued=$(lpstat -v 2>/dev/null | sed -n "s/^device for ${QUEUE}: //p")
    if [ -n "$queued" ]; then
        qh=$(uri_host "$queued")
        if [ -n "$qh" ] && nc -z -w 2 "$qh" "$PORT" 2>/dev/null; then
            printf '%s' "$qh"
            return 0
        fi
    fi

    ip=$(lpinfo -v 2>/dev/null | grep -i 'MF64' \
        | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)

    if [ -z "$ip" ] && [ -f "$IP_FILE" ]; then
        ip=$(cat "$IP_FILE")
    fi

    if [ -n "$ip" ] && nc -z -w 2 "$ip" "$PORT" 2>/dev/null; then
        printf '%s' "$ip"
        return 0
    fi

    subnets=$(ifconfig 2>/dev/null \
        | awk '/inet / && $2 != "127.0.0.1" {print $2}' \
        | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/\1/' \
        | sort -u)

    [ -z "$subnets" ] && return 1

    found=$(mktemp)
    for s in $subnets; do
        for i in {1..254}; do
            ( nc -z -w 1 "$s.$i" "$PORT" 2>/dev/null && echo "$s.$i" >> "$found" ) &
        done
    done
    wait

    ip=$(head -n 1 "$found" 2>/dev/null)
    rm -f "$found"

    [ -n "$ip" ] || return 1
    printf '%s' "$ip"
}

say "Canon MF642Cdw health check"
say ""

PRINTER_IP=$(find_printer) || PRINTER_IP=""

if [ -z "$PRINTER_IP" ]; then
    say "  printer : NOT REACHABLE on port $PORT"
    add_problem "Printer is not answering on port $PORT - powered off, asleep, or off the network"
else
    say "  printer : reachable at $PRINTER_IP:$PORT"
fi

QUEUE_URI=""
if lpstat -v 2>/dev/null | grep -q "^device for ${QUEUE}:"; then
    QUEUE_URI=$(lpstat -v 2>/dev/null | sed -n "s/^device for ${QUEUE}: //p")
    say "  queue   : $QUEUE"
    say "  address : $QUEUE_URI"

    case "$QUEUE_URI" in
        dnssd://*|ipp://*|ipps://*)
            add_problem "Queue is an AirPrint/IPP queue - this is what triggers Error 853" ;;
    esac

    if [ -n "$PRINTER_IP" ] && [ "$(uri_host "$QUEUE_URI")" != "$PRINTER_IP" ]; then
        add_problem "Queue points at $(uri_host "$QUEUE_URI"), but the printer is at $PRINTER_IP"
    fi
else
    say "  queue   : MISSING"
    add_problem "No '$QUEUE' queue exists on this Mac"
fi

DEFAULT_PRINTER=$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')
say "  default : ${DEFAULT_PRINTER:-none}"

if [ "${DEFAULT_PRINTER:-}" != "$QUEUE" ]; then
    add_problem "Default printer is '${DEFAULT_PRINTER:-none}', not $QUEUE"
fi

# Driver check - read-only, and the thing most likely to block a repair.
DRIVER_MODEL=$(lpinfo -m 2>/dev/null | awk '{print $1}' | grep -iE 'mf64[0-9]' | head -n 1)
if [ -n "$DRIVER_MODEL" ]; then
    say "  driver  : $DRIVER_MODEL"
else
    DRIVER_PPD=$(find /Library/Printers/PPDs/Contents/Resources -type f -iname '*MF64*' -print -quit 2>/dev/null)
    if [ -n "$DRIVER_PPD" ]; then
        say "  driver  : $(basename "$DRIVER_PPD")"
    else
        say "  driver  : NOT FOUND"
        add_problem "No Canon MF64x driver installed - a repair would have to install it first"
    fi
fi

say ""

if [ "$DEBUG" -eq 1 ]; then
    REPORT="$HOME/Desktop/canon-diagnostic.txt"
    {
        echo "Canon MF642Cdw diagnostic"
        echo "Generated : $(date)"
        echo "macOS     : $(sw_vers -productVersion 2>/dev/null)"
        echo "Computer  : $(scutil --get ComputerName 2>/dev/null)"
        echo "Printer IP: ${PRINTER_IP:-not found}"
        echo
        echo "=== printer ports ==="
        for port in 80 443 515 631 9100; do
            if [ -n "$PRINTER_IP" ] && nc -z -w 2 "$PRINTER_IP" "$port" 2>/dev/null; then
                echo "  $port : OPEN"
            else
                echo "  $port : closed"
            fi
        done
        echo
        echo "=== printer status (PJL) ==="
        if [ -n "$PRINTER_IP" ] && nc -z -w 2 "$PRINTER_IP" 9100 2>/dev/null; then
            printf '\033%%-12345X@PJL \r\n@PJL INFO STATUS\r\n@PJL INFO ID\r\n\033%%-12345X\r\n' \
                | nc -w 3 "$PRINTER_IP" 9100 2>/dev/null | tr -d '\r'
        else
            echo "  (9100 closed - printer asleep, off, or unreachable)"
        fi
        echo
        echo "=== queues ==="
        lpstat -p -d 2>&1
        echo
        echo "=== devices ==="
        lpstat -v 2>&1
        echo
        echo "=== this queue, in detail ==="
        lpstat -l -p "$QUEUE" 2>&1
        echo
        echo "=== Canon drivers available ==="
        lpinfo -m 2>/dev/null | grep -iE 'canon|mf64' | head -20
        echo
        echo "=== cupsd ==="
        pgrep -x cupsd >/dev/null 2>&1 && echo "  running" || echo "  NOT running"
        echo
        echo "=== recent CUPS errors ==="
        if sudo -v 2>/dev/null; then
            sudo tail -n 30 /var/log/cups/error_log 2>/dev/null || echo "  (cannot read error_log)"
        else
            echo "  (skipped - no admin rights)"
        fi
        echo
        echo "=== problems detected ==="
        if [ -z "$PROBLEMS" ]; then
            echo "  none"
        else
            printf '%s' "$PROBLEMS" | sed 's/^/  - /'
        fi
    } > "$REPORT" 2>&1

    say "Full report saved to:"
    say "   $REPORT"
    say ""
    say "Send that file when asking for help - it has everything needed."
    say ""
fi

if [ -z "$PROBLEMS" ]; then
    say "OK - printer queue is healthy."
    exit 0
fi

say "Problems found:"
printf '%s' "$PROBLEMS" | sed 's/^/   - /'

if [ "$DO_FIX" -eq 0 ]; then
    say ""
    say "Re-run without --check-only to repair."
    exit 1
fi

say ""
if [ ! -f "$SETUP" ]; then
    say "Cannot repair: setup_canon_mf642.sh not found next to this script."
    exit 1
fi

say "Repairing..."
say ""
bash "$SETUP" ${PRINTER_IP:+"$PRINTER_IP"}
status=$?

say ""
if [ $status -eq 0 ]; then
    say "Repaired."
else
    say "Repair failed (exit $status)."
fi

exit $status
