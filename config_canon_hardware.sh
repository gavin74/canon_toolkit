#!/bin/bash
IP_FILE="$(dirname "$0")/.canon_ip"
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
echo "📡 Connecting to Printer at: $PRINTER_IP:9100"

# Send hardware configuration
( printf "\033%%-12345X@PJL \r\n@PJL DEFAULT PAPER=LETTER\r\n@PJL DEFAULT ECONOMODE=OFF\r\n@PJL DEFAULT DENSITY=5\r\n@PJL DEFAULT RESOLUTION=600\r\n@PJL DEFAULT RET=ON\r\n\033%%-12345X\r\n" ) | nc -w 3 "$PRINTER_IP" 9100

echo "✅ Hardware defaults applied."

# Prompt for test page
read -p "🖨️  Print a hardware test page? (y/n): " PRINT_TEST
if [[ "$PRINT_TEST" =~ ^[Yy]$ ]]; then
    echo "📄 Sending raw PCL test page..."
    ( printf "\033%%-12345X@PJL \r\n@PJL ENTER LANGUAGE=PCL\r\n\r\nCanon MF642Cdw CLI Toolkit\r\nHardware Configuration: SUCCESS\r\nIP Address: $PRINTER_IP\r\n\r\n\014\033%%-12345X\r\n" ) | nc -w 3 "$PRINTER_IP" 9100
fi
