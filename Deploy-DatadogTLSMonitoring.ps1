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
#  Version   : 2.0.0
#  Purpose   : Automated TLS certificate monitoring deployment for Datadog
#              1.  Validates Datadog Agent is installed and running
#              2.  Scans Windows Certificate Stores (Personal, Root, CA)
#              3.  Exports certificates as .cer files
#              4.  Generates Datadog TLS conf.yaml with all instances
#              5.  Backs up existing config before overwriting
#              6.  Restarts Datadog Agent to apply new config
#              7.  Validates TLS check via agent CLI
#              8.  Generates HTML inventory report
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
#
#  Platform  : Windows Server 2016 / 2019 / 2022 / 2025
#  Requires  : Datadog Agent already installed
#              PowerShell 5.1+
#              Administrator privileges
# ==============================================================================

#Requires -RunAsAdministrator
#Requires -Version 5.1

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ==============================================================================
#  Configuration
# ==============================================================================
$ScriptRoot   = 'C:\scripts\TLSMonitor'
$ExportBase   = "$ScriptRoot\certs"
$LogPath      = "$ScriptRoot\logs"
$ReportPath   = "$ScriptRoot\reports"
$ConfPath     = 'C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml'
$AgentExe     = 'C:\Program Files\Datadog\Datadog Agent\bin\agent.exe'
$AgentSvc     = 'datadogagent'
$DaysWarning  = 30
$DaysCritical = 14
$Timeout      = 10
$AllowedTLS   = @('TLSv1.2', 'TLSv1.3')
$Version      = '2.0.0'

$StoresToScan = @(
    'Cert:\LocalMachine\My',     # Personal
    'Cert:\LocalMachine\Root',   # Trusted Root CAs
    'Cert:\LocalMachine\CA'      # Intermediate CAs
)

$Hostname = $env:COMPUTERNAME
$RunTime  = Get-Date -Format 'yyyyMMdd_HHmmss'
$SEP      = '=' * 70
$SEP2     = '-' * 60

# ==============================================================================
#  Bootstrap — create directories
# ==============================================================================
foreach ($dir in @($ScriptRoot, $ExportBase, $LogPath, $ReportPath)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$LogFile = "$LogPath\TLSMonitor_${Hostname}_${RunTime}.log"

# ==============================================================================
#  Helper functions
# ==============================================================================
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] [$Hostname] $Message"
    switch ($Level) {
        'INFO'    { Write-Host "  [ .. ] $Message" -ForegroundColor Cyan    }
        'SUCCESS' { Write-Host "  [ OK ] $Message" -ForegroundColor Green   }
        'WARN'    { Write-Host "  [WARN] $Message" -ForegroundColor Yellow  }
        'ERROR'   { Write-Host "  [FAIL] $Message" -ForegroundColor Red     }
        'DEBUG'   { Write-Host "  [    ] $Message" -ForegroundColor Gray    }
    }
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Step($n, $total, $msg) {
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
Write-Host "  Version  : $Version" -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host "  Author   : Shivam Anand  |  Sr. DevOps Engineer"
Write-Host '  Org      : Zoos Global   |  Datadog Premium Partner'
Write-Host '  Web      : www.zoosglobal.com'
Write-Host '  Email    : shivam.anand@zoosglobal.com'
Write-Host $SEP
Write-Host ''
Write-Host "  Host     : $Hostname"
Write-Host "  DryRun   : $DryRun"
Write-Host "  Stores   : $($StoresToScan.Count) stores to scan"
Write-Host "  Warn/Crit: ${DaysWarning}d / ${DaysCritical}d"
Write-Host ''

$TotalSteps = 5

# ==============================================================================
#  STEP 1 — Validate Datadog Agent
# ==============================================================================
Write-Step 1 $TotalSteps 'Validating Datadog Agent...'

try {
    $svc = Get-Service -Name $AgentSvc -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Log "Datadog Agent is running  (Status: $($svc.Status))" 'SUCCESS'
    } else {
        Write-Log "Datadog Agent not running (Status: $($svc.Status)) — attempting start..." 'WARN'
        Start-Service -Name $AgentSvc
        Start-Sleep -Seconds 5
        if ((Get-Service -Name $AgentSvc).Status -ne 'Running') {
            Write-Log 'Datadog Agent could not be started.' 'ERROR'
            exit 1
        }
        Write-Log 'Datadog Agent started successfully.' 'SUCCESS'
    }

    if (Test-Path $AgentExe) {
        $agentVer = & $AgentExe version 2>$null | Select-Object -First 1
        Write-Log "Agent version : $agentVer" 'INFO'
    }
} catch {
    Write-Log "Datadog Agent service not found: $_" 'ERROR'
    Write-Log 'Install from: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
    exit 1
}

# ==============================================================================
#  STEP 2 — Backup existing conf.yaml
# ==============================================================================
Write-Step 2 $TotalSteps 'Backing up existing conf.yaml...'

$BackupPath = $null
if (Test-Path $ConfPath) {
    $BackupPath = "$ConfPath.bak_$RunTime"
    Copy-Item -Path $ConfPath -Destination $BackupPath -Force
    Write-Log "Backup created : $BackupPath" 'SUCCESS'
} else {
    Write-Log 'No existing conf.yaml found — skipping backup.' 'INFO'
}

# ==============================================================================
#  STEP 3 — Scan & Export certificates
# ==============================================================================
Write-Step 3 $TotalSteps 'Scanning Windows Certificate Stores...'

$instances = @()
$exported  = 0
$skipped   = 0

foreach ($storePath in $StoresToScan) {
    $storeName = $storePath -replace 'Cert:\\', '' -replace '\\', '_'
    $storeDir  = "$ExportBase\$storeName"
    New-Item -ItemType Directory -Force -Path $storeDir | Out-Null

    try { $certs = Get-ChildItem -Path $storePath -ErrorAction Stop }
    catch {
        Write-Log "Cannot access store '$storePath': $_" 'WARN'
        continue
    }

    if (!$certs -or $certs.Count -eq 0) {
        Write-Log "  ⬜ $storeName — 0 certs" 'WARN'
        continue
    }

    Write-Log "  ✅ $storeName — $($certs.Count) cert(s)" 'SUCCESS'

    foreach ($cert in $certs) {
        try {
            $safeName   = ($cert.Subject -replace '[^a-zA-Z0-9]', '_')
            $safeName   = $safeName.Substring(0, [Math]::Min(50, $safeName.Length)).TrimEnd('_')
            $thumbShort = $cert.Thumbprint.Substring(0, 8)
            $filePath   = "$storeDir\${safeName}-${thumbShort}.cer"

            [System.IO.File]::WriteAllBytes($filePath,
                $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

            $daysLeft = [math]::Round(($cert.NotAfter - (Get-Date)).TotalDays)

            $instances += [PSCustomObject]@{
                local_cert_path = $filePath
                name            = "${safeName}_${thumbShort}"
                store           = $storeName
                subject         = $cert.Subject
                expiry          = $cert.NotAfter
                thumbprint      = $cert.Thumbprint
                daysLeft        = $daysLeft
            }
            $exported++
        } catch {
            Write-Log "  Skipped '$($cert.Subject)': $_" 'WARN'
            $skipped++
        }
    }
}

Write-Log "Scan complete — Exported: $exported | Skipped: $skipped" 'SUCCESS'

if ($exported -eq 0) {
    Write-Log 'No certificates found on this host. Exiting.' 'WARN'
    exit 0
}

# ==============================================================================
#  STEP 4 — Generate conf.yaml
# ==============================================================================
Write-Step 4 $TotalSteps "Generating conf.yaml ($exported instances)..."

$allowedYaml = ($AllowedTLS | ForEach-Object { "    - $_" }) -join "`n"

$yaml = @"
# ==============================================================================
#  Zoos Global -- Datadog TLS Certificate Monitoring Configuration
#  Generated  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#  Host       : $Hostname
#  Version    : $Version
#  Total Certs: $exported
#  Contact    : shivam.anand@zoosglobal.com
# ==============================================================================

init_config:
  allowed_versions:
$allowedYaml

instances:
"@

foreach ($inst in $instances) {
    $expiryStr = $inst.expiry.ToString('yyyy-MM-dd')
    $yaml += @"

  ## Store    : $($inst.store)
  ## Subject  : $($inst.subject)
  ## Expires  : $expiryStr ($($inst.daysLeft) days left)
  ## Thumb    : $($inst.thumbprint)
  - server: localhost
    local_cert_path: $($inst.local_cert_path)
    name: $($inst.name)
    days_warning: $DaysWarning
    days_critical: $DaysCritical
    timeout: $Timeout
    tls_validate_hostname: false
    tags:
      - cert_store:$($inst.store)
      - host:$Hostname
      - org:zoosglobal
      - source:windows_cert_store
      - managed_by:zoosglobal_tls_monitor

"@
}

New-Item -ItemType Directory -Force -Path (Split-Path $ConfPath) | Out-Null
$yaml | Out-File $ConfPath -Encoding UTF8
Write-Log "conf.yaml written : $ConfPath" 'SUCCESS'

# ==============================================================================
#  STEP 5 — Restart agent & validate (skip if DryRun)
# ==============================================================================
Write-Step 5 $TotalSteps 'Deploying to Datadog Agent...'

if ($DryRun) {
    Write-Log 'DryRun mode — skipping agent restart.' 'WARN'
    Write-Log "Review conf.yaml at: $ConfPath" 'INFO'
} else {
    try {
        Restart-Service -Name $AgentSvc -Force -ErrorAction Stop
        Start-Sleep -Seconds 8
        if ((Get-Service -Name $AgentSvc).Status -ne 'Running') { throw 'Agent did not start.' }
        Write-Log 'Agent restarted successfully.' 'SUCCESS'
    } catch {
        Write-Log "Agent restart failed: $_" 'ERROR'
        if ($BackupPath -and (Test-Path $BackupPath)) {
            Copy-Item -Path $BackupPath -Destination $ConfPath -Force
            Write-Log 'Config rolled back to previous backup.' 'WARN'
        }
        exit 1
    }

    Write-Log 'Running TLS check validation...' 'INFO'
    $out = & $AgentExe check tls 2>&1
    $ok  = ($out | Select-String '\[OK\]').Count
    $err = ($out | Select-String '\[ERROR\]').Count
    Write-Log "Validation — OK: $ok | ERROR: $err" $(if ($err -gt 0) { 'WARN' } else { 'SUCCESS' })
}

# ==============================================================================
#  HTML Report
# ==============================================================================
$reportFile = "$ReportPath\TLSReport_${Hostname}_${RunTime}.html"
$rows = $instances | Sort-Object daysLeft | ForEach-Object {
    $color = if ($_.daysLeft -le $DaysCritical) { '#ff4444' }
             elseif ($_.daysLeft -le $DaysWarning) { '#ffaa00' }
             else { '#00cc66' }
    "<tr>
        <td>$($_.name)</td>
        <td><span class='badge'>$($_.store)</span></td>
        <td class='small'>$($_.subject)</td>
        <td>$($_.expiry.ToString('yyyy-MM-dd'))</td>
        <td style='color:$color;font-weight:bold;text-align:center'>$($_.daysLeft)</td>
        <td class='small'>$($_.thumbprint)</td>
    </tr>"
}

$critical = ($instances | Where-Object { $_.daysLeft -le $DaysCritical }).Count
$warning  = ($instances | Where-Object { $_.daysLeft -le $DaysWarning -and $_.daysLeft -gt $DaysCritical }).Count
$healthy  = ($instances | Where-Object { $_.daysLeft -gt $DaysWarning }).Count

$html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8'>
  <title>Zoos Global - TLS Certificate Inventory | $Hostname</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:#0d0d1a;color:#e0e0e0;padding:24px}
    .header{background:linear-gradient(135deg,#0a1628,#1a2a4a);border-left:4px solid #0066ff;
            padding:20px 28px;border-radius:8px;margin-bottom:24px;
            display:flex;align-items:center;justify-content:space-between}
    .header h1{color:#0088ff;font-size:20px;letter-spacing:.5px}
    .header .sub{font-size:12px;color:#8899aa;margin-top:4px}
    .meta{text-align:right;font-size:12px;color:#8899aa}
    .meta strong{color:#fff}
    .stats{display:flex;gap:12px;margin-bottom:20px}
    .stat{background:#111827;border-radius:8px;padding:14px 20px;flex:1;text-align:center;border-top:3px solid #0066ff}
    .stat .num{font-size:28px;font-weight:700;color:#0088ff}
    .stat.crit .num{color:#ff4444}
    .stat.warn .num{color:#ffaa00}
    .stat.ok   .num{color:#00cc66}
    .stat .lbl{font-size:11px;color:#8899aa;margin-top:3px}
    table{width:100%;border-collapse:collapse;background:#111827;border-radius:8px;overflow:hidden}
    th{background:#0a1628;color:#0088ff;padding:11px 13px;text-align:left;font-size:11px;letter-spacing:1px;text-transform:uppercase}
    td{padding:9px 13px;border-bottom:1px solid #1e2a3a;font-size:12px}
    tr:hover td{background:#151f2e}
    .badge{background:#0a2040;color:#0088ff;border-radius:4px;padding:2px 7px;font-size:11px;font-family:monospace}
    .small{font-size:11px;color:#8899aa}
    .footer{margin-top:20px;text-align:center;font-size:11px;color:#445566}
    .footer a{color:#0066ff;text-decoration:none}
  </style>
</head>
<body>
  <div class='header'>
    <div>
      <h1>🔐 TLS Certificate Inventory</h1>
      <div class='sub'>Zoos Global — Infrastructure &amp; Monitoring Engineering</div>
    </div>
    <div class='meta'>
      <div>Host: <strong>$Hostname</strong></div>
      <div>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
      <div>v$Version</div>
    </div>
  </div>
  <div class='stats'>
    <div class='stat'><div class='num'>$exported</div><div class='lbl'>Total Certs</div></div>
    <div class='stat crit'><div class='num'>$critical</div><div class='lbl'>Critical (≤${DaysCritical}d)</div></div>
    <div class='stat warn'><div class='num'>$warning</div><div class='lbl'>Warning (≤${DaysWarning}d)</div></div>
    <div class='stat ok'><div class='num'>$healthy</div><div class='lbl'>Healthy</div></div>
  </div>
  <table>
    <tr><th>Name</th><th>Store</th><th>Subject</th><th>Expiry</th><th>Days Left</th><th>Thumbprint</th></tr>
    $($rows -join "`n")
  </table>
  <div class='footer'>
    Zoos Global TLS Monitor v$Version &nbsp;|&nbsp;
    <a href='mailto:shivam.anand@zoosglobal.com'>shivam.anand@zoosglobal.com</a> &nbsp;|&nbsp;
    <a href='https://www.zoosglobal.com'>www.zoosglobal.com</a>
  </div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8
Write-Log "HTML report : $reportFile" 'SUCCESS'

# ==============================================================================
#  Final Summary
# ==============================================================================
$expiring = $instances | Where-Object { $_.daysLeft -le $DaysWarning } | Sort-Object daysLeft

Write-Host ''
Write-Host $SEP -ForegroundColor Green
Write-Host '  DEPLOYMENT COMPLETE' -ForegroundColor Green
Write-Host $SEP -ForegroundColor Green
Write-Host ''
Write-Host "  Host        : $Hostname"
Write-Host "  Total Certs : $exported"
Write-Host "  Critical    : $critical" -ForegroundColor $(if ($critical -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Warning     : $warning"  -ForegroundColor $(if ($warning  -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Healthy     : $healthy"  -ForegroundColor Green
Write-Host "  Config      : $ConfPath"
Write-Host "  Report      : $reportFile"
Write-Host "  Log         : $LogFile"
Write-Host ''

if ($expiring.Count -gt 0) {
    Write-Host '  Certs expiring soon:' -ForegroundColor Yellow
    $expiring | ForEach-Object {
        $color = if ($_.daysLeft -le $DaysCritical) { 'Red' } else { 'Yellow' }
        Write-Host "    → $($_.name)  |  $($_.expiry.ToString('yyyy-MM-dd'))  ($($_.daysLeft) days)" -ForegroundColor $color
    }
    Write-Host ''
}

$instances | Group-Object store | ForEach-Object {
    Write-Host "  📦 $($_.Name) : $($_.Count) cert(s)"
}

Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Powered by Zoos Global  |  Datadog Premium Partner' -ForegroundColor Cyan
Write-Host '  www.zoosglobal.com  |  shivam.anand@zoosglobal.com' -ForegroundColor Cyan
Write-Host "  (c) $(Get-Date -Format yyyy) Zoos Global. All rights reserved." -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ''