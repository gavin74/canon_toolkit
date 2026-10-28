<#
.SYNOPSIS
    Configure a Canon MF642Cdw on Windows over a stable TCP/IP port.

.DESCRIPTION
    Windows printer auto-discovery commonly creates a WSD port, which causes the
    printer to drop offline at random. This script replaces it with a fixed
    TCP/IP port and applies colour + Letter defaults.

    The printer address is resolved in this order:
      1. -PrinterIP parameter
      2. .canon_ip beside this script
      3. interactive prompt - press Enter to sweep the local subnet(s) for port 9100

.EXAMPLE
    .\setup_canon_windows.ps1 -PrinterIP 192.168.50.173

.EXAMPLE
    .\setup_canon_windows.ps1
#>
[CmdletBinding()]
param(
    [string]$PrinterIP
)

$ErrorActionPreference = 'Stop'

$PrinterName = 'Canon_MF642Cdw_UFRII'
$DriverMatch = 'Canon MF642C/643C/644C UFR II'
$PjlPort     = 9100

function Get-LocalSubnets {
    $subnets = @()

    $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch 'Loopback|vEthernet'
        }

    foreach ($a in $addrs) {
        $octets = $a.IPAddress.Split('.')
        if ($octets.Length -eq 4) {
            $subnets += ($octets[0..2] -join '.')
        }
    }

    return ($subnets | Sort-Object -Unique)
}

function Find-PrinterBySweep {
    param([int]$TimeoutMs = 2000)

    $subnets = Get-LocalSubnets
    if (-not $subnets) { return $null }

    Write-Host ("Sweeping {0} for port {1}..." -f ($subnets -join ', '), $PjlPort)

    # Fire every connection at once, then collect whatever completed.
    $pending = @()
    foreach ($subnet in $subnets) {
        foreach ($i in 1..254) {
            $ip = "$subnet.$i"
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $iar = $client.BeginConnect($ip, $PjlPort, $null, $null)
                $pending += [pscustomobject]@{ IP = $ip; Client = $client; Async = $iar }
            }
            catch {
                $client.Close()
            }
        }
    }

    Start-Sleep -Milliseconds $TimeoutMs

    $found = @()
    foreach ($p in $pending) {
        if ($p.Async.IsCompleted) {
            try {
                $p.Client.EndConnect($p.Async)
                $found += $p.IP
            }
            catch { }
        }
        $p.Client.Close()
    }

    return ($found | Select-Object -First 1)
}

function Resolve-PrinterIP {
    param([string]$Explicit)

    if ($Explicit) { return $Explicit }

    $ipFile = Join-Path $PSScriptRoot '.canon_ip'
    if (Test-Path $ipFile) {
        $cached = (Get-Content $ipFile -Raw).Trim()
        if ($cached -match '^\d{1,3}(\.\d{1,3}){3}$') { return $cached }
    }

    while ($true) {
        $answer = Read-Host 'Printer IP address (Enter to sweep local subnets)'

        if ($answer -and $answer -match '^\d{1,3}(\.\d{1,3}){3}$') { return $answer }

        if ([string]::IsNullOrWhiteSpace($answer)) {
            $found = Find-PrinterBySweep
            if ($found) {
                Write-Host "Found printer at $found" -ForegroundColor Green
                return $found
            }
            Write-Host 'No host answered on port 9100.' -ForegroundColor Yellow
            return $null
        }

        Write-Host 'Not a valid IPv4 address.' -ForegroundColor Yellow
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Run this script as Administrator.' -ForegroundColor Red
    exit 1
}

$PrinterIP = Resolve-PrinterIP -Explicit $PrinterIP

if (-not $PrinterIP) {
    Write-Host 'Could not determine the printer address. Pass -PrinterIP.' -ForegroundColor Red
    exit 1
}

# Cache the address the same way the Unix scripts do.
$ipFile = Join-Path $PSScriptRoot '.canon_ip'
Set-Content -Path $ipFile -Value $PrinterIP

$PortName = "IP_$PrinterIP"
Write-Host "Printer: $PrinterIP"

Write-Host "Creating stable TCP/IP port '$PortName' (bypasses WSD)..."
if (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) {
    Write-Host 'Port already exists, reusing it.'
}
else {
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
}

$driver = Get-PrinterDriver |
    Where-Object { $_.Name -match [regex]::Escape($DriverMatch) } |
    Select-Object -First 1

if (-not $driver) {
    Write-Host 'Canon UFR II driver not found. Install the Canon driver package first.' -ForegroundColor Red
    exit 1
}

if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing queue '$PrinterName'..."
    Remove-Printer -Name $PrinterName
}

Write-Host 'Installing printer queue...'
Add-Printer -Name $PrinterName -PortName $PortName -DriverName $driver.Name

Write-Host 'Applying colour + Letter defaults...'
Set-PrintConfiguration -PrinterName $PrinterName -Color $true -PaperSize Letter

Write-Host "Done - '$PrinterName' now prints to $PrinterIP over TCP/IP." -ForegroundColor Green
