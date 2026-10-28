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
      3. interactive prompt

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

function Resolve-PrinterIP {
    param([string]$Explicit)

    if ($Explicit) { return $Explicit }

    $ipFile = Join-Path $PSScriptRoot '.canon_ip'
    if (Test-Path $ipFile) {
        $cached = (Get-Content $ipFile -Raw).Trim()
        if ($cached -match '^\d{1,3}(\.\d{1,3}){3}$') { return $cached }
    }

    while ($true) {
        $answer = Read-Host 'Printer IP address'
        if ($answer -match '^\d{1,3}(\.\d{1,3}){3}$') { return $answer }
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
$PortName  = "IP_$PrinterIP"
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
