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
#  Script    : Zoos Global TLS Monitor - Setup Script
#  Version   : 2.0.0
#  Purpose   : Fully automated one-time setup per host
#              1.  Validates Datadog Agent is installed and running
#              2.  Creates C:\scripts\TLSMonitor directory structure
#              3.  Copies Deploy-TLSMonitor.ps1 to destination
#              4.  Unblocks scripts (removes Zone.Identifier)
#              5.  Enables Windows Certificate Lifecycle event log
#              6.  Runs Deploy-TLSMonitor.ps1 immediately (first run)
#              7.  Registers EVENT-DRIVEN task (fires on cert install)
#              8.  Registers FALLBACK task (every 7 days at 02:00)
#              9.  Prints final status summary
# ------------------------------------------------------------------------------
#  Author    : Shivam Anand
#  Title     : Sr. DevOps Engineer | Engineering
#  Org       : Zoos Global
#  Email     : shivam.anand@zoosglobal.com
#  Web       : www.zoosglobal.com
#  Address   : Violena, Pali Hill, Bandra West, Mumbai - 400050
# ------------------------------------------------------------------------------
#  Usage     : Run as Administrator once per host, from the folder
#              containing Deploy-TLSMonitor.ps1 -- fully automated
#
#              PowerShell.exe -ExecutionPolicy Bypass -File .\setup.ps1
#
#  Scaling   : Two triggers registered per host:
#              EVENT  — fires automatically when any cert is installed
#                       (Windows Event ID 1006, no polling delay)
#              WEEKLY — fallback every Sunday at 02:00 AM
#                       (catches certs missed by event trigger)
#
#  Platform  : Windows Server 2016 / 2019 / 2022 / 2025
#  Requires  : Datadog Agent already installed
#              PowerShell 5.1+
#              Administrator privileges
# ==============================================================================

#Requires -RunAsAdministrator
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

# ==============================================================================
#  Configuration
# ==============================================================================
$ScriptsDir    = 'C:\scripts\TLSMonitor'
$SourceScript  = 'Deploy-TLSMonitor.ps1'
$TargetScript  = "$ScriptsDir\Deploy-TLSMonitor.ps1"
$LogPath       = "$ScriptsDir\logs"
$AgentSvc      = 'datadogagent'
$TaskFolder    = '\ZoosGlobal'
$TaskEvent     = 'ZoosGlobal-TLS-CertInstall-Trigger'
$TaskFallback  = 'ZoosGlobal-TLS-Weekly-Fallback'
$Version       = '2.0.0'

# Windows Event that fires when a cert is added to ANY local store
# Log: Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational
# Event ID 1006 = certificate added
$CertEventLog  = 'Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational'
$CertEventId   = 1006

$SEP  = '=' * 70
$SEP2 = '-' * 60
$TotalSteps = 9

New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
$SetupLog = "$LogPath\Setup_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ==============================================================================
#  Helper functions
# ==============================================================================
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'INFO'    { Write-Host "  [ .. ] $Message" -ForegroundColor Cyan   }
        'SUCCESS' { Write-Host "  [ OK ] $Message" -ForegroundColor Green  }
        'WARN'    { Write-Host "  [WARN] $Message" -ForegroundColor Yellow }
        'ERROR'   { Write-Host "  [FAIL] $Message" -ForegroundColor Red    }
    }
    Add-Content -Path $SetupLog -Value $line -ErrorAction SilentlyContinue
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
Write-Host '  ZOOS GLOBAL -- TLS Monitor Setup' -ForegroundColor Cyan
Write-Host "  Version  : $Version" -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host "  Author   : Shivam Anand  |  Sr. DevOps Engineer"
Write-Host '  Org      : Zoos Global   |  Datadog Premium Partner'
Write-Host '  Web      : www.zoosglobal.com'
Write-Host '  Email    : shivam.anand@zoosglobal.com'
Write-Host $SEP
Write-Host ''
Write-Host "  Config:"
Write-Host "    Install path : $ScriptsDir"
Write-Host "    Task (event) : $TaskEvent"
Write-Host "    Task (weekly): $TaskFallback"
Write-Host "    Trigger 1    : On cert install (Event ID $CertEventId) — instant"
Write-Host "    Trigger 2    : Every Sunday @ 02:00 AM — fallback"
Write-Host ''
Write-Host '  Starting automated setup -- no input required...' -ForegroundColor Green
Write-Host ''

# ==============================================================================
#  STEP 1 — Validate Datadog Agent
# ==============================================================================
Write-Step 1 $TotalSteps 'Checking Datadog Agent service...'
try {
    $svc = Get-Service -Name $AgentSvc -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Log "Datadog Agent is running  (Status: $($svc.Status))" 'SUCCESS'
    } else {
        Write-Log "Datadog Agent not running (Status: $($svc.Status)) — attempting start..." 'WARN'
        Start-Service -Name $AgentSvc
        Start-Sleep -Seconds 6
        if ((Get-Service -Name $AgentSvc).Status -ne 'Running') {
            Write-Log 'Datadog Agent could not be started.' 'ERROR'
            Write-Log 'Download: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
            exit 1
        }
        Write-Log 'Datadog Agent started successfully.' 'SUCCESS'
    }
} catch {
    Write-Log "Datadog Agent service not found: $_" 'ERROR'
    Write-Log 'Install from: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
    exit 1
}

# ==============================================================================
#  STEP 2 — Create directory structure
# ==============================================================================
Write-Step 2 $TotalSteps "Creating directory: $ScriptsDir..."
try {
    foreach ($dir in @($ScriptsDir, "$ScriptsDir\certs", "$ScriptsDir\logs", "$ScriptsDir\reports")) {
        if (Test-Path $dir) {
            Write-Log "Exists : $dir" 'INFO'
        } else {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Write-Log "Created: $dir" 'SUCCESS'
        }
    }
} catch {
    Write-Log "Failed to create directories: $_" 'ERROR'
    exit 1
}

# ==============================================================================
#  STEP 3 — Copy Deploy-TLSMonitor.ps1
# ==============================================================================
Write-Step 3 $TotalSteps "Copying $SourceScript to $TargetScript..."
try {
    $sourcePath = Join-Path (Get-Location).Path $SourceScript
    if (-not (Test-Path $sourcePath)) {
        Write-Log "$SourceScript not found in: $(Get-Location)" 'ERROR'
        Write-Log 'Run setup.ps1 from the same folder as Deploy-TLSMonitor.ps1' 'INFO'
        exit 1
    }
    Copy-Item -Path $sourcePath -Destination $TargetScript -Force
    $copied = Get-Item $TargetScript
    Write-Log "Copied : $TargetScript" 'SUCCESS'
    Write-Log "Size   : $([math]::Round($copied.Length / 1KB, 2)) KB" 'INFO'
} catch {
    Write-Log "Failed to copy script: $_" 'ERROR'
    exit 1
}

# ==============================================================================
#  STEP 4 — Unblock scripts
# ==============================================================================
Write-Step 4 $TotalSteps 'Unblocking scripts (removing Zone.Identifier)...'
try {
    foreach ($f in @($TargetScript, $MyInvocation.MyCommand.Path, (Join-Path (Get-Location).Path $SourceScript))) {
        if ($f -and (Test-Path $f)) {
            Unblock-File -Path $f -ErrorAction SilentlyContinue
            Write-Log "Unblocked: $f" 'SUCCESS'
        }
    }
} catch {
    Write-Log "Unblock warning (non-fatal): $_" 'WARN'
}

# ==============================================================================
#  STEP 5 — Enable Certificate Lifecycle event log
# ==============================================================================
Write-Step 5 $TotalSteps 'Enabling Certificate Lifecycle event log...'
try {
    $logObj = Get-WinEvent -ListLog $CertEventLog -ErrorAction Stop
    if (-not $logObj.IsEnabled) {
        wevtutil set-log $CertEventLog /enabled:true
        Write-Log 'Certificate Lifecycle event log enabled.' 'SUCCESS'
    } else {
        Write-Log 'Certificate Lifecycle event log already enabled.' 'SUCCESS'
    }
    Write-Log "Event log  : $CertEventLog" 'INFO'
    Write-Log "Trigger ID : Event $CertEventId (certificate added)" 'INFO'
} catch {
    Write-Log "Could not enable cert lifecycle log: $_ (non-fatal — event task will be registered anyway)" 'WARN'
}

# ==============================================================================
#  STEP 6 — Run immediately (first deployment)
# ==============================================================================
Write-Step 6 $TotalSteps 'Running initial deployment...'
Write-Log 'Executing Deploy-TLSMonitor.ps1 (first run)...' 'INFO'
Write-Host ''

& powershell.exe -ExecutionPolicy Bypass -NonInteractive -File $TargetScript

if ($LASTEXITCODE -ne 0) {
    Write-Log "Initial deployment failed (exit code: $LASTEXITCODE)" 'ERROR'
    exit 1
}
Write-Host ''
Write-Log 'Initial deployment complete.' 'SUCCESS'

# ==============================================================================
#  Shared task components
# ==============================================================================
$taskAction = New-ScheduledTaskAction `
    -Execute  'PowerShell.exe' `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TargetScript`""

$taskSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit          (New-TimeSpan -Hours 1) `
    -StartWhenAvailable `
    -MultipleInstances           IgnoreNew `
    -RestartCount                3 `
    -RestartInterval             (New-TimeSpan -Minutes 5) `
    -RunOnlyIfNetworkAvailable:$false

$taskPrincipal = New-ScheduledTaskPrincipal `
    -UserId    'NT AUTHORITY\SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel  Highest

# ==============================================================================
#  STEP 7 — Register EVENT-DRIVEN task (fires instantly on cert install)
# ==============================================================================
Write-Step 7 $TotalSteps "Registering event-driven task: '$TaskEvent'..."

# Remove old version if exists
$existing = Get-ScheduledTask -TaskName $TaskEvent -TaskPath $TaskFolder -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskEvent -TaskPath $TaskFolder -Confirm:$false
    Write-Log 'Removed existing event task.' 'INFO'
}

try {
    $eventTrigger = New-CimInstance -Namespace ROOT\Microsoft\Windows\TaskScheduler `
        -ClassName MSFT_TaskEventTrigger `
        -ClientOnly `
        -Property @{
            Enabled      = $true
            Subscription = "<QueryList><Query Id='0' Path='$CertEventLog'><Select Path='$CertEventLog'>*[System[EventID=$CertEventId]]</Select></Query></QueryList>"
            Delay        = 'PT30S'  # 30-second delay after cert install before running
        }

    Register-ScheduledTask `
        -TaskName    $TaskEvent `
        -TaskPath    $TaskFolder `
        -Action      $taskAction `
        -Trigger     $eventTrigger `
        -Settings    $taskSettings `
        -Principal   $taskPrincipal `
        -Description "Zoos Global — Fires instantly when a certificate is installed (Event ID $CertEventId). Updates Datadog TLS monitoring config automatically." | Out-Null

    Write-Log "Event task registered : $TaskFolder\$TaskEvent" 'SUCCESS'
    Write-Log 'Trigger               : On cert install (Event ID 1006) + 30s delay' 'INFO'
} catch {
    Write-Log "Event task registration warning: $_ (falling back to weekly task only)" 'WARN'
}

# ==============================================================================
#  STEP 8 — Register FALLBACK WEEKLY task (every Sunday at 02:00)
# ==============================================================================
Write-Step 8 $TotalSteps "Registering weekly fallback task: '$TaskFallback'..."

$existing = Get-ScheduledTask -TaskName $TaskFallback -TaskPath $TaskFolder -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskFallback -TaskPath $TaskFolder -Confirm:$false
    Write-Log 'Removed existing fallback task.' 'INFO'
}

try {
    $weeklyTrigger = New-ScheduledTaskTrigger `
        -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At '02:00'

    Register-ScheduledTask `
        -TaskName    $TaskFallback `
        -TaskPath    $TaskFolder `
        -Action      $taskAction `
        -Trigger     $weeklyTrigger `
        -Settings    $taskSettings `
        -Principal   $taskPrincipal `
        -Description "Zoos Global — Weekly fallback scan every Sunday at 02:00. Catches any certificates missed by the event-driven trigger." | Out-Null

    Write-Log "Fallback task registered : $TaskFolder\$TaskFallback" 'SUCCESS'
    Write-Log 'Trigger                  : Every Sunday at 02:00 AM' 'INFO'
} catch {
    Write-Log "Fallback task registration failed: $_" 'ERROR'
    exit 1
}

# ==============================================================================
#  STEP 9 — Verify tasks
# ==============================================================================
Write-Step 9 $TotalSteps 'Verifying scheduled tasks...'

$infoEvent    = Get-ScheduledTaskInfo -TaskName $TaskEvent    -TaskPath $TaskFolder -ErrorAction SilentlyContinue
$infoFallback = Get-ScheduledTaskInfo -TaskName $TaskFallback -TaskPath $TaskFolder -ErrorAction SilentlyContinue

if ($infoEvent) {
    Write-Log "Event task    : registered and ready" 'SUCCESS'
} else {
    Write-Log "Event task    : could not be verified (check Task Scheduler manually)" 'WARN'
}
if ($infoFallback) {
    Write-Log "Fallback task : registered — next run $($infoFallback.NextRunTime)" 'SUCCESS'
} else {
    Write-Log "Fallback task : could not be verified" 'WARN'
}

# ==============================================================================
#  Final Summary
# ==============================================================================
Write-Host ''
Write-Host $SEP -ForegroundColor Green
Write-Host '  SETUP COMPLETE -- All steps passed' -ForegroundColor Green
Write-Host $SEP -ForegroundColor Green
Write-Host ''
Write-Host '  What was configured:'
Write-Host "    Host          : $($env:COMPUTERNAME)"
Write-Host "    Script path   : $TargetScript"
Write-Host "    Setup log     : $SetupLog"
Write-Host ''
Write-Host '  Scheduled Tasks (Task Scheduler > ZoosGlobal):' -ForegroundColor Yellow
Write-Host ''
Write-Host "    📡 $TaskEvent"
Write-Host "       Trigger : When any certificate is installed on this host"
Write-Host "       Delay   : 30 seconds after install"
Write-Host "       Runs as : NT AUTHORITY\SYSTEM"
Write-Host ''
Write-Host "    🕑 $TaskFallback"
Write-Host "       Trigger : Every Sunday at 02:00 AM"
if ($infoFallback) {
    Write-Host "       Next run: $($infoFallback.NextRunTime)"
}
Write-Host "       Runs as : NT AUTHORITY\SYSTEM"
Write-Host ''
Write-Host '  Manage tasks:'
Write-Host "    Start-ScheduledTask  -TaskName '$TaskEvent'    -TaskPath '$TaskFolder'"
Write-Host "    Start-ScheduledTask  -TaskName '$TaskFallback' -TaskPath '$TaskFolder'"
Write-Host "    Get-ScheduledTask                              -TaskPath '$TaskFolder'"
Write-Host ''
Write-Host '  Remove setup completely:'
Write-Host "    Unregister-ScheduledTask -TaskName '$TaskEvent'    -TaskPath '$TaskFolder' -Confirm:`$false"
Write-Host "    Unregister-ScheduledTask -TaskName '$TaskFallback' -TaskPath '$TaskFolder' -Confirm:`$false"
Write-Host "    Remove-Item -Recurse -Force '$ScriptsDir'"
Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Powered by Zoos Global  |  Datadog Premium Partner' -ForegroundColor Cyan
Write-Host '  www.zoosglobal.com  |  shivam.anand@zoosglobal.com' -ForegroundColor Cyan
Write-Host "  (c) $(Get-Date -Format yyyy) Zoos Global. All rights reserved." -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ''