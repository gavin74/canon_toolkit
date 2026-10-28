#!/bin/bash
IP_FILE=".canon_ip"
if [ -n "$1" ]; then
    PRINTER_IP=$1
else
    PRINTER_IP=$(lpinfo -v 2>/dev/null | grep -i "MF642" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    [ -z "$PRINTER_IP" ] && [ -f "$IP_FILE" ] && PRINTER_IP=$(cat "$IP_FILE")
    
    if [ -z "$PRINTER_IP" ]; then
        read -p "⚠️ Auto-discovery failed. Enter IP manually (or press Enter to sweep active subnets): " PRINTER_IP
        if [ -z "$PRINTER_IP" ]; then
            if command -v ipconfig.exe &> /dev/null; then
                SUBNETS=$(ipconfig.exe | grep -a IPv4 | grep -Eo '([0-9]{1,3}\.){3}' | sort -u | sed 's/\.$//')
            else
                SUBNETS=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | grep -Eo '([0-9]{1,3}\.){3}' | sort -u | sed 's/\.$//')
            fi
            
            echo "🔍 Sweeping active subnets for Port 9100 (~3 seconds)..."
            rm -f /tmp/canon_found
            for subnet in $SUBNETS; do
                for i in {1..254}; do
                    (nc -z -w 1 $subnet.$i 9100 2>/dev/null && echo "$subnet.$i" >> /tmp/canon_found) &
                done
            done
            wait
            PRINTER_IP=$(cat /tmp/canon_found 2>/dev/null | head -n 1)
            [ -z "$PRINTER_IP" ] && echo "❌ Scan failed to find printer." && exit 1
        fi
    fi
fi

echo "$PRINTER_IP" > "$IP_FILE"
echo "📡 Querying Printer at: $PRINTER_IP:9100"

( printf "\033%%-12345X@PJL \r\n@PJL INFO PRODINFO\r\n@PJL INFO STATUS\r\n@PJL INFO CONFIG\r\n@PJL INFO VARIABLES\r\n\033%%-12345X\r\n" ) | nc -w 5 "$PRINTER_IP" 9100
