# Canon MF642Cdw CLI Toolkit

## Do this

Make the button — paste this into Terminal:

```bash
curl -fsSL "https://raw.githubusercontent.com/gavin74/canon_toolkit/main/Fix%20Canon%20Printer.command" -o "$HOME/Desktop/Fix Printer.command" && chmod +x "$HOME/Desktop/Fix Printer.command"
```

Then **double-click `Fix Printer`** on your Desktop and choose **1**.

It will ask for your Mac password. That's normal — installing a printer needs it.

At the end it offers to print a test page. **Say yes** — a correct-looking queue and a
real printed page are different things, and the page is the only proof.

---

## Details you don't have to read

### What the choices mean

The button shows what's currently set up, then asks:

| Choice | What it does |
|---|---|
| **1** Check and fix | Repairs anything that's wrong. Start here. |
| **2** Wipe and reinstall | Deletes this printer's queues and sets it up from scratch. Use if 1 doesn't help. |
| **3** Check only | Reports what's wrong and changes nothing. |
| **4** Full diagnostic | Saves a detailed report to the Desktop, including printer status, queue detail, drivers and recent CUPS errors. Changes nothing. |

If you type anything else, it says so and changes nothing.

After a successful install or wipe, it asks whether to print a test page. If you say
yes, it watches the job through the queue for 45 seconds:

- job left the queue → accepted and printed. If no page appears, the problem is the
  printer, not the Mac.
- job still sitting in the queue → it was accepted but never printed, which means the
  printer is offline or the driver is wrong.

Choice 4 writes `canon-diagnostic.txt` to the Desktop. If something needs explaining,
that file has the answers in it.

### Windows

Paste into PowerShell **as Administrator**:

```powershell
$z="$env:TEMP\canon.zip"; iwr https://github.com/gavin74/canon_toolkit/archive/refs/heads/main.zip -OutFile $z; Expand-Archive $z -DestinationPath $env:TEMP -Force; & "$env:TEMP\canon_toolkit-main\setup_canon_windows.ps1"
```

Windows points at one fixed address. If the printer ever gets a different one, Windows
stops printing with no error message. Give the printer a **DHCP reservation** on the
router so its address never changes — that's a one-off job in the router's admin page,
and it's the single most useful thing you can do for this setup.

### If the password is rejected

It's `sudo`, so it wants the **macOS login password of an administrator** — the one
you type to unlock the Mac. Not your Apple ID.

Check whether the account is an admin:

```bash
id -Gn | tr ' ' '\n' | grep -x admin && echo "you are an admin" || echo "NOT an admin"
```

If it says **NOT an admin**, no password will work. Someone with admin rights has to
either grant it (**System Settings → Users & Groups → Allow this user to administer
this computer**) or add the printer once themselves. macOS requires admin rights to
add a printer whether you use this script or System Settings.

On a managed (school/work) Mac, an MDM profile can block printer changes entirely.
Then the script fails at `lpadmin` and nothing here can fix it.

### Why this printer keeps breaking on macOS

Installing the Canon driver and adding the printer are two separate things, and macOS
gets the second one wrong. Add the printer through System Settings and macOS discovers
it over Bonjour and creates an **AirPrint** queue using Apple's generic driver — even
when the Canon UFR II driver is installed. The vendor driver is only used if a queue
is explicitly bound to it.

AirPrint is what triggers **Error 853** on this model. It also drops paper-type
settings, which is why glossy prints smear: the fuser never learns the media type, so
it never slows down.

So don't add this printer through System Settings. If someone does, re-run the button.

### How it finds the printer

In order, stopping at the first hit:

1. An address passed on the command line
2. `lpinfo` auto-discovery
3. `.canon_ip` — the address it found last time, **only if it still answers**
4. The address an existing queue already points at, **if it still answers**
5. The ARP table, then a full subnet sweep (slow; `SKIP_SCAN=1` disables it)
6. Asking you

If the printer can't be reached at all, it asks before touching anything — it won't
tear down a working queue for a printer that's just asleep.

### How it picks the driver

Not by filename — Canon's PPD may be gzipped or generically named. It asks CUPS what
models it actually has:

```bash
lpinfo -m | grep -iE 'mf64[0-9]'
```

and falls back to a PPD under `/Library/Printers/PPDs/Contents/Resources` matching
`*MF64*`. If neither turns up anything it offers
`brew install --cask canon-ufrii-driver` (maintained upstream, checksum-pinned), and
failing that it stops **before touching any queue**.

### Command line, if you prefer

```bash
./canon-healthcheck.sh                # check, then repair
./canon-healthcheck.sh --check-only   # diagnose only, change nothing
./setup_canon_mf642.sh                # install / rebuild
./setup_canon_mf642.sh --force        # ignore the cached address, rebuild from scratch
```

Exit code is `0` when healthy or repaired, `1` when still broken.

`config_canon_hardware.sh` pushes firmware defaults — Letter, Toner Save off, density
5, 600 dpi — directly over PJL, independent of any driver:

```bash
./config_canon_hardware.sh 192.168.50.174   # omit the IP to auto-discover
./query_canon_status.sh                     # read back status
```

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No Canon MF64x driver found` | Canon driver not installed | `brew install --cask canon-ufrii-driver`, or install from Canon's support page |
| `This queue still reports AirPrint` | The PPD didn't take | Confirm the driver installed, then re-run |
| `No printer address given` | Nothing found on port 9100 | Pass the address: `setup_canon_mf642.sh 192.168.50.174` |
| `brew: command not found` | No Homebrew | Install from https://brew.sh, or use Canon's installer |
| macOS won't open the `.command` | Gatekeeper | Right-click → **Open** |
| `.command` opens in TextEdit | Executable bit lost | `chmod +x "$HOME/Desktop/Fix Printer.command"` |
| Glossy prints still smear | Media Type left on Plain | Set **Heavy** or **Glossy** in the print dialog |
| Windows printer drops offline | WSD port | Re-run the Windows script |
| `lpadmin: Operation not permitted` | Not elevated | Re-run; the script escalates itself |

### Known expiry

Recent macOS releases warn that `lpadmin: Printer drivers are deprecated and will stop
working in a future version of macOS`. LPD + UFR II is the working approach today, but
this is a countdown rather than a permanent fix.
