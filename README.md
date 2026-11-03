# Canon MF642Cdw CLI Toolkit

Fixes three recurring problems with the Canon imageCLASS MF642Cdw:

- **Error 853** — the printer crashes with a memory error when macOS drives it via AirPrint.
- **Faint prints** — Toner Save left on, or density too low.
- **Goes offline at random on Windows** — auto-discovery assigns a flaky WSD port.

The scripts talk to the printer directly over **PJL on TCP 9100**, or rebuild the
print queue using Canon's official UFR II driver.

## One click on a Mac

**Step 1 — make the button.** Paste this into Terminal. It writes a
double-clickable file straight to the Desktop:

```bash
curl -fsSL "https://raw.githubusercontent.com/gavin74/canon_toolkit/main/Fix%20Canon%20Printer.command" -o "$HOME/Desktop/Fix Printer.command" && chmod +x "$HOME/Desktop/Fix Printer.command"
```

**Step 2 — double-click `Fix Printer` on the Desktop.** It finds the printer,
installs the driver if needed, removes any AirPrint queue, and rebuilds it
properly. It re-downloads the current script each run, so it never goes stale.

> **It will ask for a password.** That's `sudo`. Use the **macOS account password
> of an administrator** — the same one you type to unlock the Mac. It is *not*
> your Apple ID password. If it's rejected, the account isn't an administrator;
> see [Needs an administrator account](#needs-an-administrator-account).

### Or one line, no button

```bash
curl -fsSLo /tmp/canon.zip https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip && unzip -oq /tmp/canon.zip -d /tmp && bash /tmp/canon_toolkit-main/setup_canon_mf642.sh
```

### Already working, but not printing?

```bash
curl -fsSLo /tmp/canon.zip https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip && unzip -oq /tmp/canon.zip -d /tmp && bash /tmp/canon_toolkit-main/canon-healthcheck.sh
```

That reports what's wrong *and* repairs it.

### Windows

Paste into PowerShell **as Administrator**:

```powershell
$z="$env:TEMP\canon.zip"; iwr https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip -OutFile $z; Expand-Archive $z -DestinationPath $env:TEMP -Force; & "$env:TEMP\canon_toolkit-main\setup_canon_windows.ps1"
```

All of these find the printer themselves — no IP address needed.

---

## Needs an administrator account

Adding a print queue is a system-level change. macOS requires admin rights for it
whether you use this script or System Settings, so there's no way around it.

Check whether the account is an administrator:

```bash
id -Gn | tr ' ' '\n' | grep -x admin && echo "you are an admin" || echo "NOT an admin"
```

If it says **NOT an admin**, you need someone with admin rights to either:

- grant the account admin: **System Settings → Users & Groups → (user) → Allow this
  user to administer this computer**, or
- add the printer themselves once. After that it keeps working for everyone.

If you *are* an admin and the password is still rejected, make sure you're using the
**login password**, not the Apple ID. On a managed or school/work Mac, an MDM
profile may block printer changes entirely — in that case the script will fail at
`lpadmin` and nothing else will help.

---

## Install on a Mac

The repo is public — nothing to sign in to, no git, no GitHub account.

The one-liner is at the top of this page. If you'd rather not use Terminal at all:

1. Open this link — it downloads immediately, no sign-in:
   **https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip**
2. Open **Downloads** and double-click the `.zip`.
3. Open the folder that appears and **double-click `Install Canon Printer.command`**.
4. Type your Mac login password when asked — that's for installing the driver.

Both routes do the same thing: find the printer, install the driver if missing,
remove the AirPrint queue, and rebuild it properly.

If the Canon driver isn't installed, the script offers to install it via Homebrew.
Without Homebrew it prints the manual download instructions and stops cleanly.

### If the file won't run

**"cannot be opened because it is from an unidentified developer"**
Right-click the file → **Open** → then **Open** again. Only needed once.

**"you do not have appropriate access privileges"** (or it opens in TextEdit)
Rare — GitHub's zip preserves the executable bit — but if it happens, the flag was
lost. Open **Terminal**, type `cd ` (with a trailing space), drag the folder into
the Terminal window, press Return, then:

```bash
chmod +x "Install Canon Printer.command"
```

---

## When it breaks again

Every Mac keeps its **own** print queue. When someone adds the printer through
System Settings, macOS quietly creates an **AirPrint** queue and the trouble comes
back. When that happens, don't debug it — **double-click
`Fix Canon Printer.command`**. Rename it "Fix Printer" and put it on the Desktop so
anyone in the house can use it.

It re-downloads the current script and re-runs it, repairing whichever of these
broke:

- the queue is pointing at a stale IP address
- macOS created an AirPrint queue behind your back
- the printer was added with the wrong driver

### Put the button on any Mac

Run this once on each Mac. It writes the button straight to the Desktop — no
unzipping, no dragging:

```bash
curl -fsSL "https://raw.githubusercontent.com/gavin74/canon_toolkit/main/Fix%20Canon%20Printer.command" -o "$HOME/Desktop/Fix Printer.command" && chmod +x "$HOME/Desktop/Fix Printer.command"
```

Then double-click **Fix Printer**.

The file is self-contained: it downloads the current script from GitHub each time it
runs, so it never goes stale and doesn't need this repo sitting on the machine.

If macOS says it can't be opened, right-click it → **Open** → **Open** again. That's
only needed once.

No terminal, no questions, no IP to look up. If you'd rather keep one file handy,
this is a single self-contained script — it fetches what it needs.

### Health check from the command line

`canon-healthcheck.sh` inspects the Mac and repairs it if needed. It checks that
the printer answers, that the queue exists, that the queue points at the printer's
*current* address (not a stale one), that it isn't an AirPrint queue, and that it's
the default.

```bash
./canon-healthcheck.sh                # check, then repair if anything is wrong
./canon-healthcheck.sh --check-only   # diagnose only, change nothing
```

Exit code is `0` when healthy or repaired, `1` when still broken — so it's safe to
use from a scheduled job or a login hook.

To see what was actually wrong before repairing it, run `lpstat -v` on the Mac. The
device URI shows whether it's pointing at an IP (`lpd://192.168.50.174`) or at an
AirPrint service (`dnssd://...`).

---

## Why macOS breaks this printer

Installing the Canon driver and adding the printer are **two separate things**, and
macOS gets the second one wrong. Add the printer through System Settings and macOS
discovers it over Bonjour and creates an **AirPrint** queue using Apple's generic
driver — even when the Canon UFR II driver is already installed. The vendor driver
is only used if a queue is explicitly bound to it.

AirPrint is what triggers **Error 853**. It also drops paper-type settings, which is
why glossy prints smear: the fuser never learns the media type, so it never slows
down.

`setup_canon_mf642.sh` fixes the queue half. It deletes every queue pointing at the
printer — matched on the *device URI*, so it catches AirPrint queues whatever macOS
named them — then builds one queue bound to the Canon UFR II driver over **LPD**.

**Do not re-add the printer through System Settings → Printers & Scanners → +.**
That puts the AirPrint queue straight back. Re-run the script instead.

## Driver detection

Not by filename — Canon's PPD may be gzipped or generically named. The script asks
CUPS what models it actually has:

```bash
lpinfo -m | grep -iE 'mf64[0-9]'
```

and falls back to a PPD file under `/Library/Printers/PPDs/Contents/Resources`
matching `*MF64*`. If neither turns up anything, it stops **before touching any
print queue** — it will not delete your working queues to install a broken one.

The driver itself comes from the Homebrew cask `canon-ufrii-driver` (currently
10.19.26, autobumped, SHA-256 pinned). The script offers to install it with a y/N
prompt if it's missing; it never installs anything silently. Without Homebrew,
install **UFR II/UFRII LT Printer Driver & Utilities for Mac** from Canon's support
page — Canon publishes no stable direct URL, so that step can't be automated.

## Confirming it worked

The script prints the driver the finished queue is bound to:

```
   Driver: Canon MF642C/643C/644C UFR II
```

If that line contains **AirPrint**, the PPD didn't take and you'll get Error 853
again.

## Finding the printer

Every script resolves the address in this order, stopping at the first hit:

1. An address passed on the command line (`-PrinterIP` on Windows)
2. `.canon_ip` — a cached last-known address beside the script
3. A scan of every local subnet for hosts listening on port 9100
4. An interactive prompt

`setup_canon_mf642.sh` scans automatically *before* asking, so a fresh Mac needs no
arguments. The others scan when you press Enter at the prompt.

`.canon_ip` is written automatically and is git-ignored — per-network state, not
something worth committing.

## Windows

Auto-discovery normally creates a WSD port, which drops offline at random. The
script replaces it with a fixed TCP/IP port and applies colour/Letter defaults.

**One line** — open PowerShell **as Administrator** and paste:

```powershell
$z="$env:TEMP\canon.zip"; iwr https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip -OutFile $z; Expand-Archive $z -DestinationPath $env:TEMP -Force; & "$env:TEMP\canon_toolkit-main\setup_canon_windows.ps1"
```

Or from a downloaded copy:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup_canon_windows.ps1
```

Omit `-PrinterIP` to scan, fall back to `.canon_ip`, or be prompted.

### The printer must have a stable address

The Windows queue points at one fixed IP. If the printer gets a new address — a new
DHCP lease, or a different access point — Windows stops printing with no obvious
error, while macOS keeps working because it scans for the printer each time.

Give the printer a **DHCP reservation** on the router, or a static address outside
the DHCP pool. That's the durable fix.

## Hardware defaults (any platform)

Forces Letter paper, Toner Save off, density 5 and 600 dpi into the printer's
firmware defaults — independent of any driver, and it survives driver reinstalls.

```bash
./config_canon_hardware.sh 192.168.50.173   # omit the IP to auto-discover
./query_canon_status.sh                     # read back product info and status
```

## Paper and media

- **Standard printing** — 20 lb paper in the main cassette.
- **Photo printing** — laser-rated glossy stock in the front multi-purpose tray.
  In the print dialog you *must* set Media Type to **Heavy** or **Glossy**, so the
  fuser slows down and melts the toner. On Plain the toner smears and rubs off.

## Requirements

| Task | Needs |
|---|---|
| macOS setup | macOS, `sudo`, and either Homebrew or the Canon driver pre-installed |
| Windows setup | PowerShell **as Administrator**, Canon UFR II driver installed |
| PJL scripts (hardware defaults / status) | `bash`, `netcat` (`nc`), `lpinfo` from CUPS |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No Canon MF64x driver found` | Canon driver not installed | `brew install --cask canon-ufrii-driver`, or install it from Canon's support page |
| `This queue still reports AirPrint` | The PPD didn't take | Confirm the driver installed, then re-run |
| `No printer address given` | Scan found nothing on port 9100 | Pass the address: `bash setup_canon_mf642.sh 192.168.50.173` |
| `brew: command not found` | Homebrew not installed | Install from https://brew.sh, or install the driver manually |
| macOS won't open the `.command` | Gatekeeper quarantine | Right-click → **Open** |
| `.command` opens in TextEdit | Executable flag lost in the zip | `chmod +x "Install Canon Printer.command"` |
| Glossy prints still smear | Media Type left on Plain | Set **Heavy** or **Glossy** in the print dialog |
| Printer drops offline on Windows | WSD port | Re-run `setup_canon_windows.ps1` |
| `lpadmin: Operation not permitted` | Not elevated | Re-run; the script escalates itself |

## Known expiry: Apple is deprecating PPD queues

Recent macOS releases warn that `lpadmin: Printer drivers are deprecated and will
stop working in a future version of macOS`. LPD + UFR II is the working approach
today, but this is a countdown rather than a permanent fix.
