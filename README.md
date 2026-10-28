# Canon MF642Cdw CLI Toolkit

Scripts to fix three recurring problems with the Canon imageCLASS MF642Cdw:

- **Error 853** — the printer crashes with a memory error when driven by macOS AirPrint.
- **Faint prints** — Toner Save left on, or density too low.
- **Printer randomly going offline** — Windows auto-discovery assigns a flaky WSD port.

The scripts either talk to the printer directly over **PJL on TCP 9100**, or rebuild
the print queue using the official Canon UFR II driver.

## Finding the printer

Every script resolves the address in the same order:

1. An address passed on the command line (`-PrinterIP` on Windows)
2. `.canon_ip` — a cached last-known address beside the script
3. Interactive prompt

`config_canon_hardware.sh` and `query_canon_status.sh` add one more step: press
Enter at the prompt and they **sweep every local subnet for hosts listening on
port 9100**. That takes a few seconds and finds the printer even after its address
has changed.

`.canon_ip` is written automatically and is git-ignored — it is per-network state,
not something worth committing.

## Requirements

| Platform | Needs |
|---|---|
| Linux / WSL / macOS | `bash`, `netcat` (`nc`), and `lpinfo` from CUPS for auto-discovery |
| macOS setup | Canon UFR II driver installed, `sudo` |
| Windows setup | PowerShell **as Administrator**, Canon UFR II driver installed |

## Hardware configuration (any platform)

Forces Letter paper, Toner Save off, density 5 and 600 dpi directly into the
printer's firmware defaults — independent of any driver, and it survives driver
reinstalls.

```bash
chmod +x config_canon_hardware.sh query_canon_status.sh
./config_canon_hardware.sh 192.168.50.173   # omit the IP to auto-discover
./query_canon_status.sh                     # read back product info and status
```

## macOS

AirPrint's driver is what triggers Error 853. This script deletes existing
Canon/AirPrint queues and rebuilds them over **LPD** with the Canon UFR II PPD.

```bash
sudo ./setup_canon_mf642.sh
```

## Windows

Auto-discovery typically produces a WSD port that drops offline at random. This
script replaces it with a fixed TCP/IP port and applies colour/Letter defaults.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup_canon_windows.ps1 -PrinterIP 192.168.50.173
```

Omit `-PrinterIP` to fall back to `.canon_ip` or be prompted.

## Hardware notes

- **Standard printing** — load 20 lb paper in the main cassette.
- **Photo printing** — laser-rated glossy paper in the front multi-purpose tray.
  In the print dialog you *must* set Media Type to **Heavy** or **Glossy**, so the
  fuser slows down and actually melts the toner. On plain settings the toner smears
  and rubs off.
