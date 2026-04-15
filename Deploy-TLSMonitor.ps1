# ==============================================================================
#
#   ███████╗ ██████╗  ██████╗ ███████╗     ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗
#   ╚══███╔╝██╔═══██╗██╔═══██╗██╔════╝    ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║
#     ███╔╝ ██║   ██║██║   ██║███████╗    ██║  ███╗██║     ██║   ██║██████╔╝███████║██║
#    ███╔╝  ██║   ██║██║   ██║╚════██║    ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║
#   ███████╗╚██████╔╝╚██████╔╝███████║    ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗
#   ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝     ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
#
# ==============================================================================
#  Script    : Datadog TLS Certificate Monitor - Deployment Script
#  Version   : 2.1.0
#  Purpose   : Automated TLS certificate monitoring deployment for Datadog
#              1.  Validates Datadog Agent is installed and running
#              2.  Scans Windows Certificate Stores (Personal, Root, CA)
#              3.  Exports certificates as .cer files
#              4.  Generates Datadog TLS conf.yaml with all instances
#              5.  Backs up existing config before overwriting
#              6.  Restarts Datadog Agent to apply new config
#              7.  Validates TLS check via agent CLI
#              8.  Generates plain text inventory report
#              9.  Prints final status summary
# ------------------------------------------------------------------------------
#  Author    : Shivam Anand
#  Title     : Sr. DevOps Engineer | Engineering
#  Org       : Zoos Global
#  Email     : shivam.anand@zoosglobal.com
#  Web       : www.zoosglobal.com
#  Address   : Violena, Pali Hill, Bandra West, Mumbai - 400050
# ------------------------------------------------------------------------------
#  Usage     : Run as Administrator on each target host
#
#              PowerShell.exe -ExecutionPolicy Bypass -File .\Deploy-TLSMonitor.ps1
#
#              Optional parameters:
#              -DryRun    Generate conf.yaml only, skip agent restart
#              -LogPath   Custom log directory (default: C:\scripts\TLSMonitor\logs)
#
#  Platform  : Windows Server 2016 / 2019 / 2022 / 2025
#  Requires  : Datadog Agent already installed
#              PowerShell 5.1+
#              Administrator privileges
# ==============================================================================

#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$LogPath = 'C:\scripts\TLSMonitor\logs'
)

$ErrorActionPreference = 'Stop'

# ==============================================================================
#  Configuration
# ==============================================================================
$Config = @{
    ExportBase   = 'C:\scripts\TLSMonitor\certs'
    ReportPath   = 'C:\scripts\TLSMonitor\reports'
    ConfPath     = 'C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml'
    AgentExe     = 'C:\Program Files\Datadog\Datadog Agent\bin\agent.exe'
    AgentService = 'datadogagent'
    DaysWarning  = 30
    DaysCritical = 14
    Timeout      = 10
    AllowedTLS   = @('TLSv1.2', 'TLSv1.3')
    StoresToScan = @(
        'Cert:\LocalMachine\My',     # Personal
        'Cert:\LocalMachine\Root',   # Trusted Root CAs
        'Cert:\LocalMachine\CA'      # Intermediate CAs
    )
}

$ScriptVersion = '2.1.0'
$Hostname      = $env:COMPUTERNAME
$RunTime       = Get-Date -Format 'yyyyMMdd_HHmmss'
$SEP           = '=' * 70
$SEP2          = '-' * 60

# ==============================================================================
#  Bootstrap directories
# ==============================================================================
foreach ($dir in @($LogPath, $Config.ExportBase, $Config.ReportPath)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$LogFile = "$LogPath\DatadogTLS_${Hostname}_${RunTime}.log"

# ==============================================================================
#  Helper functions
# ==============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')]
        [string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'INFO'    { Write-Host "  [ .. ] $Message" -ForegroundColor Cyan    }
        'SUCCESS' { Write-Host "  [ OK ] $Message" -ForegroundColor Green   }
        'WARN'    { Write-Host "  [WARN] $Message" -ForegroundColor Yellow  }
        'ERROR'   { Write-Host "  [FAIL] $Message" -ForegroundColor Red     }
        'DEBUG'   { Write-Host "  [    ] $Message" -ForegroundColor Gray    }
    }
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Step {
    param([int]$n, [int]$total, [string]$msg)
    Write-Host ''
    Write-Host "  [$n/$total] $msg" -ForegroundColor Yellow
    Write-Host "  $SEP2" -ForegroundColor DarkGray
}

# ==============================================================================
#  Banner
# ==============================================================================
Clear-Host
Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  ZOOS GLOBAL -- Datadog TLS Certificate Monitor' -ForegroundColor Cyan
Write-Host "  Version  : $ScriptVersion" -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Author   : Shivam Anand  |  Sr. DevOps Engineer'
Write-Host '  Org      : Zoos Global   |  Datadog Premium Partner'
Write-Host '  Web      : www.zoosglobal.com'
Write-Host '  Email    : shivam.anand@zoosglobal.com'
Write-Host $SEP
Write-Host ''
Write-Host "  Host     : $Hostname"
Write-Host "  DryRun   : $DryRun"
Write-Host "  Stores   : $($Config.StoresToScan.Count) stores to scan"
Write-Host "  Warn/Crit: $($Config.DaysWarning)d / $($Config.DaysCritical)d"
Write-Host ''

$TotalSteps = 6

# ==============================================================================
#  STEP 1 - Prerequisites
# ==============================================================================
Write-Step 1 $TotalSteps 'Validating prerequisites...'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Log 'Script must be run as Administrator.' 'ERROR'
    exit 1
}

if (-not (Test-Path $Config.AgentExe)) {
    Write-Log "Datadog Agent not found at: $($Config.AgentExe)" 'ERROR'
    Write-Log 'Install from: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
    exit 1
}

$svc = Get-Service -Name $Config.AgentService -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Log "Datadog Agent service '$($Config.AgentService)' not found." 'ERROR'
    exit 1
}

if ($svc.Status -ne 'Running') {
    Write-Log "Agent not running - attempting start..." 'WARN'
    Start-Service -Name $Config.AgentService
    Start-Sleep -Seconds 6
    if ((Get-Service -Name $Config.AgentService).Status -ne 'Running') {
        Write-Log 'Datadog Agent could not be started.' 'ERROR'
        exit 1
    }
}

$agentVer = & $Config.AgentExe version 2>$null | Select-Object -First 1
Write-Log "Agent        : $agentVer" 'SUCCESS'
Write-Log 'Prerequisites passed.' 'SUCCESS'

# ==============================================================================
#  STEP 2 - Backup existing conf.yaml
# ==============================================================================
Write-Step 2 $TotalSteps 'Backing up existing conf.yaml...'

$BackupPath = $null
if (Test-Path $Config.ConfPath) {
    $BackupPath = "$($Config.ConfPath).bak_$RunTime"
    Copy-Item -Path $Config.ConfPath -Destination $BackupPath -Force
    Write-Log "Backup created : $BackupPath" 'SUCCESS'
} else {
    Write-Log 'No existing conf.yaml found - skipping backup.' 'INFO'
}

# ==============================================================================
#  STEP 3 - Scan & Export certificates from Windows Certificate Stores
# ==============================================================================
Write-Step 3 $TotalSteps 'Scanning Windows Certificate Stores...'

$instances    = @()
$totalStores  = 0
$totalCerts   = 0
$skippedCerts = 0

foreach ($storePath in $Config.StoresToScan) {
    $storeName = $storePath -replace 'Cert:\\', '' -replace '\\', '_'
    $storeDir  = "$($Config.ExportBase)\$storeName"
    New-Item -ItemType Directory -Force -Path $storeDir | Out-Null

    try {
        $certs = Get-ChildItem -Path $storePath -ErrorAction Stop
    } catch {
        Write-Log "Cannot access store '$storePath': $_" 'WARN'
        continue
    }

    if (-not $certs -or $certs.Count -eq 0) {
        Write-Log "Store $storeName - 0 certs" 'WARN'
        continue
    }

    Write-Log "Store $storeName - $($certs.Count) cert(s)" 'SUCCESS'
    $totalStores++

    foreach ($cert in $certs) {
        try {
            $safeName = ($cert.Subject -replace '[^a-zA-Z0-9]', '_')
            if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'cert' }
            $safeName   = $safeName.Substring(0, [Math]::Min(50, $safeName.Length)).TrimEnd('_')
            $thumbShort = $cert.Thumbprint.Substring(0, 8)
            $filePath   = "$storeDir\${safeName}-${thumbShort}.cer"

            [System.IO.File]::WriteAllBytes(
                $filePath,
                $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            )

            $daysLeft = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays)

            $instances += [PSCustomObject]@{
                local_cert_path = $filePath
                name            = "${safeName}_${thumbShort}"
                store           = $storeName
                subject         = $cert.Subject
                expiry          = $cert.NotAfter
                thumbprint      = $cert.Thumbprint
                issuer          = $cert.Issuer
                daysLeft        = $daysLeft
            }
            $totalCerts++
        } catch {
            Write-Log "Skipped '$($cert.Subject)': $_" 'WARN'
            $skippedCerts++
        }
    }
}

Write-Log "Scan complete - Stores: $totalStores | Exported: $totalCerts | Skipped: $skippedCerts" 'SUCCESS'

if ($totalCerts -eq 0) {
    Write-Log 'No certificates exported. Nothing to deploy.' 'WARN'
    exit 0
}

# ==============================================================================
#  STEP 4 - Generate conf.yaml
# ==============================================================================
Write-Step 4 $TotalSteps "Generating conf.yaml ($totalCerts instances)..."

$allowedVersionsYaml = ($Config.AllowedTLS | ForEach-Object { "    - $_" }) -join "`n"

$yaml = @"
# ==============================================================================
#  Zoos Global -- Datadog TLS Certificate Monitoring Configuration
#  Generated  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#  Host       : $Hostname
#  Version    : $ScriptVersion
#  Total Certs: $totalCerts
#  Contact    : shivam.anand@zoosglobal.com
# ==============================================================================

init_config:
  allowed_versions:
$allowedVersionsYaml

instances:
"@

foreach ($inst in $instances) {
    $expiryStr = $inst.expiry.ToString('yyyy-MM-dd')
    $yaml += @"

  ## Store      : $($inst.store)
  ## Subject    : $($inst.subject)
  ## Issuer     : $($inst.issuer)
  ## Expires    : $expiryStr ($($inst.daysLeft) days left)
  ## Thumbprint : $($inst.thumbprint)
  - server: localhost
    local_cert_path: $($inst.local_cert_path)
    name: $($inst.name)
    days_warning: $($Config.DaysWarning)
    days_critical: $($Config.DaysCritical)
    timeout: $($Config.Timeout)
    tls_validate_hostname: false
    tags:
      - cert_store:$($inst.store)
      - host:$Hostname
      - source:windows_cert_store
"@
}

New-Item -ItemType Directory -Force -Path (Split-Path $Config.ConfPath) | Out-Null
$yaml | Out-File $Config.ConfPath -Encoding UTF8
Write-Log "conf.yaml written : $($Config.ConfPath)" 'SUCCESS'

# ==============================================================================
#  STEP 5 - Deploy to Datadog Agent
# ==============================================================================
Write-Step 5 $TotalSteps 'Deploying to Datadog Agent...'

if ($DryRun) {
    Write-Log 'DryRun mode - skipping agent restart.' 'WARN'
    Write-Log "Review conf.yaml at: $($Config.ConfPath)" 'INFO'
} else {
    try {
        Restart-Service -Name $Config.AgentService -Force -ErrorAction Stop
        Start-Sleep -Seconds 8
        if ((Get-Service -Name $Config.AgentService).Status -ne 'Running') {
            throw 'Agent did not start after restart.'
        }
        Write-Log 'Agent restarted successfully.' 'SUCCESS'
    } catch {
        Write-Log "Agent restart failed: $_" 'ERROR'
        if ($BackupPath -and (Test-Path $BackupPath)) {
            Copy-Item -Path $BackupPath -Destination $Config.ConfPath -Force
            Write-Log 'Config rolled back to previous backup.' 'WARN'
        }
        exit 1
    }

    Write-Log 'Running TLS check validation...' 'INFO'
    $checkOutput  = & $Config.AgentExe check tls 2>&1
    $okCount      = ($checkOutput | Select-String '\[OK\]').Count
    $errCount     = ($checkOutput | Select-String '\[ERROR\]').Count
    Write-Log "Validation - OK: $okCount | ERROR: $errCount" $(if ($errCount -gt 0) { 'WARN' } else { 'SUCCESS' })
}

# ==============================================================================
#  STEP 6 - Plain text report + summary
# ==============================================================================
Write-Step 6 $TotalSteps 'Generating report and summary...'

$critical    = ($instances | Where-Object { $_.daysLeft -le $Config.DaysCritical }).Count
$warning     = ($instances | Where-Object { $_.daysLeft -le $Config.DaysWarning -and $_.daysLeft -gt $Config.DaysCritical }).Count
$healthy     = ($instances | Where-Object { $_.daysLeft -gt $Config.DaysWarning }).Count
$expiringSoon = $instances | Where-Object { $_.daysLeft -le $Config.DaysWarning } | Sort-Object daysLeft
$reportFile  = "$($Config.ReportPath)\TLSReport_${Hostname}_${RunTime}.txt"

$reportLines  = @()
$reportLines += $SEP
$reportLines += '  Zoos Global - TLS Certificate Inventory'
$reportLines += "  Version   : $ScriptVersion"
$reportLines += $SEP
$reportLines += "  Host      : $Hostname"
$reportLines += "  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += "  Total     : $totalCerts"
$reportLines += "  Critical  : $critical"
$reportLines += "  Warning   : $warning"
$reportLines += "  Healthy   : $healthy"
$reportLines += $SEP
$reportLines += ''
$reportLines += '  Certificate Details:'
$reportLines += $SEP2

foreach ($item in ($instances | Sort-Object daysLeft)) {
    $status = if ($item.daysLeft -le $Config.DaysCritical) { 'CRITICAL' }
              elseif ($item.daysLeft -le $Config.DaysWarning) { 'WARNING' }
              else { 'HEALTHY' }
    $reportLines += "  Name       : $($item.name)"
    $reportLines += "  Store      : $($item.store)"
    $reportLines += "  Subject    : $($item.subject)"
    $reportLines += "  Issuer     : $($item.issuer)"
    $reportLines += "  Expiry     : $($item.expiry.ToString('yyyy-MM-dd'))"
    $reportLines += "  Days Left  : $($item.daysLeft)"
    $reportLines += "  Thumbprint : $($item.thumbprint)"
    $reportLines += "  Cert Path  : $($item.local_cert_path)"
    $reportLines += "  Status     : $status"
    $reportLines += $SEP2
}

$reportLines | Out-File $reportFile -Encoding UTF8
Write-Log "Text report : $reportFile" 'SUCCESS'

# Final summary to console
Write-Host ''
Write-Host $SEP -ForegroundColor Green
Write-Host '  DEPLOYMENT COMPLETE' -ForegroundColor Green
Write-Host $SEP -ForegroundColor Green
Write-Host ''
Write-Host "  Host        : $Hostname"
Write-Host "  Total Certs : $totalCerts"
Write-Host "  Critical    : $critical" -ForegroundColor $(if ($critical -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Warning     : $warning"  -ForegroundColor $(if ($warning -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Healthy     : $healthy"  -ForegroundColor Green
Write-Host "  Config      : $($Config.ConfPath)"
Write-Host "  Report      : $reportFile"
Write-Host "  Log         : $LogFile"
Write-Host ''

if ($expiringSoon.Count -gt 0) {
    Write-Host '  Certs expiring soon:' -ForegroundColor Yellow
    foreach ($e in $expiringSoon) {
        $col = if ($e.daysLeft -le $Config.DaysCritical) { 'Red' } else { 'Yellow' }
        Write-Host "    -> $($e.name)  |  $($e.expiry.ToString('yyyy-MM-dd'))  ($($e.daysLeft) days)" -ForegroundColor $col
    }
    Write-Host ''
}

$instances | Group-Object store | ForEach-Object {
    Write-Host "  [STORE] $($_.Name) : $($_.Count) cert(s)"
}

Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Powered by Zoos Global  |  Datadog Premium Partner' -ForegroundColor Cyan
Write-Host '  www.zoosglobal.com  |  shivam.anand@zoosglobal.com' -ForegroundColor Cyan
Write-Host "  (c) $(Get-Date -Format yyyy) Zoos Global. All rights reserved." -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ''