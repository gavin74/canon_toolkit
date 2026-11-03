#!/bin/bash
#
# canon-testpage.sh - write a colour test page as a PDF.
#
#   ./canon-testpage.sh OUTPUT.pdf [queue] [driver] [printer-ip]
#
# Pure bash + coreutils: no ghostscript, no Python, nothing to install. The PDF
# is assembled by hand so it works on a bare macOS install.
#
# It is deliberately loud: red header, colour swatches, and a circle. If the
# swatches come out muddy or one is missing, that tells you something a page of
# black text never would.
#
set -u

OUT="${1:-}"
QUEUE="${2:-Canon_MF642Cdw_UFRII}"
DRIVER="${3:-Canon UFR II}"
PRINTER="${4:-unknown}"

if [ -z "$OUT" ]; then
    echo "usage: $(basename "$0") OUTPUT.pdf [queue] [driver] [printer-ip]" >&2
    exit 2
fi

# PDF strings are delimited by ( ) so those, and backslash, must be escaped.
pdf_escape() {
    printf '%s' "$1" | sed 's/[\\()]/\\&/g'
}

DATE_STR=$(date '+%Y-%m-%d %H:%M')
QUEUE_E=$(pdf_escape "$QUEUE")
DRIVER_E=$(pdf_escape "$DRIVER")
PRINTER_E=$(pdf_escape "$PRINTER")

# --- page content ----------------------------------------------------------
# 612x792 points (US Letter). Origin bottom-left.
CONTENT="1 1 1 rg 0 0 612 792 re f
0.886 0.110 0.220 rg 0 612 612 180 re f
1 1 1 rg BT /F1 46 Tf 54 722 Td (UP THE BORO) Tj ET
1 1 1 rg BT /F2 17 Tf 54 694 Td (Canon MF642Cdw - colour test page) Tj ET
0.15 0.15 0.15 rg BT /F2 13 Tf 54 566 Td (Swatches distinct, every step visible, page clean? Then printing works.) Tj ET
0 1 1 rg 54 480 64 64 re f
1 0 1 rg 128 480 64 64 re f
1 1 0 rg 202 480 64 64 re f
0 0 0 rg 276 480 64 64 re f
0.886 0.110 0.220 rg 350 480 64 64 re f
0.13 0.55 0.20 rg 424 480 64 64 re f
0.15 0.15 0.15 rg BT /F2 10 Tf 54 464 Td (cyan) Tj ET
0.15 0.15 0.15 rg BT /F2 10 Tf 128 464 Td (magenta) Tj ET
0.15 0.15 0.15 rg BT /F2 10 Tf 202 464 Td (yellow) Tj ET
0.15 0.15 0.15 rg BT /F2 10 Tf 276 464 Td (black) Tj ET
0.15 0.15 0.15 rg BT /F2 10 Tf 350 464 Td (boro red) Tj ET
0.15 0.15 0.15 rg BT /F2 10 Tf 424 464 Td (green) Tj ET
0.16 0.02 0.04 rg 54 382 62 52 re f
0.28 0.03 0.07 rg 116 382 62 52 re f
0.40 0.05 0.10 rg 178 382 62 52 re f
0.52 0.06 0.13 rg 240 382 62 52 re f
0.64 0.08 0.16 rg 302 382 62 52 re f
0.76 0.09 0.19 rg 364 382 62 52 re f
0.886 0.110 0.220 rg 426 382 62 52 re f
1.00 0.22 0.32 rg 488 382 62 52 re f
0.15 0.15 0.15 rg BT /F2 10 Tf 54 364 Td (gradation - every step should be distinguishable, none banded) Tj ET
0.15 0.15 0.15 rg BT /F2 12 Tf 54 312 Td (Date      : $DATE_STR) Tj ET
0.15 0.15 0.15 rg BT /F2 12 Tf 54 292 Td (Queue     : $QUEUE_E) Tj ET
0.15 0.15 0.15 rg BT /F2 12 Tf 54 272 Td (Driver    : $DRIVER_E) Tj ET
0.15 0.15 0.15 rg BT /F2 12 Tf 54 252 Td (Printer   : $PRINTER_E) Tj ET
0.15 0.15 0.15 rg BT /F2 11 Tf 54 210 Td (github.com/gavin74/canon_toolkit) Tj ET
0.886 0.110 0.220 rg 444 232 m 504 232 504 265.14 504 292 c 504 318.86 477.14 345.14 444 345.14 c 410.86 345.14 384 318.86 384 292 c 384 265.14 410.86 232 444 232 c f
1 1 1 rg BT /F1 18 Tf 405 286 Td (UTB) Tj ET
0 0 0 rg 0 0 612 64 re f
1 1 1 rg BT /F1 22 Tf 54 26 Td (UP THE BORO) Tj ET
1 1 1 rg BT /F2 10 Tf 380 26 Td (red, white, and no streaking) Tj ET"

# --- assemble the PDF, tracking byte offsets for the xref table -------------
: > "$OUT" || exit 1
printf '%%PDF-1.4\n' >> "$OUT"

OFF1=$(wc -c < "$OUT" | tr -d ' ')
printf '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' >> "$OUT"

OFF2=$(wc -c < "$OUT" | tr -d ' ')
printf '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' >> "$OUT"

OFF3=$(wc -c < "$OUT" | tr -d ' ')
printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>\nendobj\n' >> "$OUT"

CLEN=$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')
OFF4=$(wc -c < "$OUT" | tr -d ' ')
printf '4 0 obj\n<< /Length %s >>\nstream\n' "$CLEN" >> "$OUT"
printf '%s' "$CONTENT" >> "$OUT"
printf '\nendstream\nendobj\n' >> "$OUT"

OFF5=$(wc -c < "$OUT" | tr -d ' ')
printf '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n' >> "$OUT"

OFF6=$(wc -c < "$OUT" | tr -d ' ')
printf '6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n' >> "$OUT"

XREF=$(wc -c < "$OUT" | tr -d ' ')
{
    printf 'xref\n0 7\n'
    printf '0000000000 65535 f \n'
    printf '%010d 00000 n \n' "$OFF1"
    printf '%010d 00000 n \n' "$OFF2"
    printf '%010d 00000 n \n' "$OFF3"
    printf '%010d 00000 n \n' "$OFF4"
    printf '%010d 00000 n \n' "$OFF5"
    printf '%010d 00000 n \n' "$OFF6"
    printf 'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n%s\n%%%%EOF\n' "$XREF"
} >> "$OUT"

echo "$OUT"
