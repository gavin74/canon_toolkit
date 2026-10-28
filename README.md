# Canon MF642Cdw CLI Toolkit

Scripts to fix three recurring problems with the Canon imageCLASS MF642Cdw:

- **Error 853** — the printer crashes with a memory error when driven by macOS AirPrint.
- **Faint prints** — Toner Save left on, or density too low.
- **Printer randomly going offline** — Windows auto-discovery assigns a flaky WSD port.

The scripts either talk to the printer directly over **PJL on TCP 9100**, or rebuild
the print queue using the official Canon UFR II driver.

## Finding the printer

Every script resolves the address the same way:

1. An address passed on the command line (`-PrinterIP` on Windows)
2. `.canon_ip` — a cached last-known address beside the script
3. Interactive prompt

`config_canon_hardware.sh`, `query_canon_status.sh` and `setup_canon_windows.ps1`
add a fourth step: press Enter at the prompt and they **sweep every local subnet
for hosts listening on port 9100**. That takes a couple of seconds and finds the
printer even after its address has changed.

`setup_canon_mf642.sh` (macOS) is the exception — `lpinfo`, then the cached
address, then a prompt. No sweep.

`.canon_ip` is written automatically and is git-ignored — it is per-network state,
not something worth committing.

## Requirements

| Platform | Needs |
|---|---|
| Linux / WSL / macOS | `bash`, `netcat` (`nc`), and `lpinfo` from CUPS for auto-discovery |
| macOS setup | Canon UFR II driver installed (see below), `sudo` |
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

### The actual problem: macOS uses AirPrint, not the Canon driver

Installing the Canon driver and adding the printer are **two separate things**,
and macOS gets the second one wrong. Add the printer through System Settings and
macOS discovers it over Bonjour and creates an **AirPrint** queue using Apple's
generic driver — even when the Canon UFR II driver is sitting right there
installed. The vendor driver is only used if a queue is explicitly bound to it.

AirPrint is what triggers **Error 853** on the MF642Cdw. It also removes paper-type
settings, which is why glossy photo prints smear: the fuser never slows down,
because AirPrint never tells it the media type.

`setup_canon_mf642.sh` fixes the second half of the problem. It deletes every
queue pointing at the printer — matched on the device URI, so it catches AirPrint
queues regardless of what macOS named them — then builds one queue bound to the
Canon UFR II PPD over **LPD**.

### Do not add the printer through System Settings

If you re-add it via **System Settings → Printers & Scanners → +**, you get the
AirPrint queue straight back. Re-run the script instead.

### 1. Install the Canon driver

The script does **not** install the driver, and Canon publishes no stable direct
download URL, so this step is manual. Get **UFR II/UFRII LT Printer Driver &
Utilities for Mac** from Canon's support page for the MF642Cdw and run the
installer.

At time of writing the current release is **V10.19.26**, covering macOS 11.7.11
through macOS 27.0. Check the support page rather than trusting that number — it
moves.

The script looks for the PPD under `/Library/Printers/PPDs/Contents/Resources`
and exits with a clear message if it isn't there. It does that check *before*
prompting for a password.

### 2. Build the queue

```bash
gh repo clone gavin74/canon_toolkit /tmp/canon_toolkit
bash /tmp/canon_toolkit/setup_canon_mf642.sh 192.168.50.173
```

Or as a single line:

```bash
gh repo clone gavin74/canon_toolkit /tmp/canon_toolkit && bash /tmp/canon_toolkit/setup_canon_mf642.sh 192.168.50.173
```

- `gh` must be authenticated — the repo is private.
- No `sudo` prefix; the script escalates itself where it needs to.
- Omit the IP to auto-discover via `lpinfo`, fall back to `.canon_ip`, or be
  prompted. Unlike the PJL scripts, this one does not sweep the subnet.

### 3. Verify it actually took

The script prints the driver the finished queue is bound to:

```
   Driver: Canon MF642C/643C/644C UFR II
```

If that line says anything containing **AirPrint**, the PPD didn't take and the
queue will hit Error 853 again. The script exits before that point if the driver
is missing, so seeing this line at all is a good sign.

### Caveat: Apple is deprecating PPD queues

Recent macOS releases warn that `lpadmin: Printer drivers are deprecated and will
stop working in a future version of macOS`. LPD + UFR II is still the working
approach today, but this is a known expiry date rather than a permanent fix.



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
