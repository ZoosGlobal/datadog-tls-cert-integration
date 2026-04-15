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
#  Version   : 2.1.0
#  Purpose   : Fully automated one-time setup per host
#              1.  Validates Datadog Agent is installed and running
#              2.  Creates C:\scripts\TLSMonitor directory structure
#              3.  Copies Deploy-TLSMonitor.ps1 to destination
#              4.  Unblocks scripts (removes Zone.Identifier)
#              5.  Runs Deploy-TLSMonitor.ps1 immediately (first run)
#              6.  Creates weekly Scheduled Task in root Task Scheduler
#                  (every Sunday at 02:00 AM, NT AUTHORITY\SYSTEM)
#              7.  Prints final status summary
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
#  Task      : Task is created in the DEFAULT root Task Scheduler Library.
#              No custom folder/subpath is used. This avoids path duplication
#              and event-trigger type mismatch issues on all Windows versions.
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
$ScriptsDir   = 'C:\scripts\TLSMonitor'
$SourceScript = 'Deploy-TLSMonitor.ps1'
$TargetScript = "$ScriptsDir\Deploy-TLSMonitor.ps1"
$LogPath      = "$ScriptsDir\logs"
$AgentSvc     = 'datadogagent'
$TaskName     = 'ZoosGlobal-TLS-Weekly-Fallback'
$TaskDesc     = 'Zoos Global TLS Monitor - weekly cert scan every Sunday at 02:00 AM, runs as SYSTEM'
$Version      = '2.1.0'
$TotalSteps   = 7

$SEP  = '=' * 70
$SEP2 = '-' * 60

# ==============================================================================
#  Bootstrap log directory
# ==============================================================================
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
Write-Host '  ZOOS GLOBAL -- TLS Monitor Setup' -ForegroundColor Cyan
Write-Host "  Version  : $Version" -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Author   : Shivam Anand  |  Sr. DevOps Engineer'
Write-Host '  Org      : Zoos Global   |  Datadog Premium Partner'
Write-Host '  Web      : www.zoosglobal.com'
Write-Host '  Email    : shivam.anand@zoosglobal.com'
Write-Host $SEP
Write-Host ''
Write-Host '  Config:'
Write-Host "    Install path : $ScriptsDir"
Write-Host "    Task name    : $TaskName"
Write-Host '    Task folder  : Root (Task Scheduler Library)'
Write-Host '    Trigger      : Every Sunday @ 02:00 AM'
Write-Host '    Runs as      : NT AUTHORITY\SYSTEM'
Write-Host ''
Write-Host '  Starting automated setup -- no input required...' -ForegroundColor Green
Write-Host ''

# ==============================================================================
#  STEP 1 - Validate Datadog Agent
# ==============================================================================
Write-Step 1 $TotalSteps 'Validating Datadog Agent...'
try {
    $svc = Get-Service -Name $AgentSvc -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Log "Datadog Agent is running (Status: $($svc.Status))" 'SUCCESS'
    } else {
        Write-Log "Agent not running ($($svc.Status)) - attempting start..." 'WARN'
        Start-Service -Name $AgentSvc
        Start-Sleep -Seconds 6
        if ((Get-Service -Name $AgentSvc).Status -ne 'Running') {
            Write-Log 'Datadog Agent could not be started.' 'ERROR'
            Write-Log 'Download: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
            exit 1
        }
        Write-Log 'Datadog Agent started successfully.' 'SUCCESS'
    }
    $agentExe = 'C:\Program Files\Datadog\Datadog Agent\bin\agent.exe'
    if (Test-Path $agentExe) {
        $ver = & $agentExe version 2>$null | Select-Object -First 1
        Write-Log "Agent version : $ver" 'INFO'
    }
} catch {
    Write-Log "Datadog Agent service not found: $_" 'ERROR'
    Write-Log 'Install from: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi' 'INFO'
    exit 1
}

# ==============================================================================
#  STEP 2 - Create directory structure
# ==============================================================================
Write-Step 2 $TotalSteps "Creating directory structure in $ScriptsDir..."
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
#  STEP 3 - Copy Deploy-TLSMonitor.ps1
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
    Write-Log "Date   : $($copied.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
} catch {
    Write-Log "Failed to copy script: $_" 'ERROR'
    exit 1
}

# ==============================================================================
#  STEP 4 - Unblock scripts
# ==============================================================================
Write-Step 4 $TotalSteps 'Unblocking scripts (removing Zone.Identifier)...'
try {
    $toUnblock = @(
        $TargetScript,
        $MyInvocation.MyCommand.Path,
        (Join-Path (Get-Location).Path $SourceScript)
    )
    foreach ($f in $toUnblock) {
        if ($f -and (Test-Path $f)) {
            Unblock-File -Path $f -ErrorAction SilentlyContinue
            Write-Log "Unblocked: $f" 'SUCCESS'
        }
    }
} catch {
    Write-Log "Unblock warning (non-fatal): $_" 'WARN'
}

# ==============================================================================
#  STEP 5 - Initial deployment (first run)
# ==============================================================================
Write-Step 5 $TotalSteps 'Running initial deployment (first run)...'
Write-Log 'Executing Deploy-TLSMonitor.ps1...' 'INFO'
Write-Host ''

& PowerShell.exe -ExecutionPolicy Bypass -NonInteractive -File $TargetScript

if ($LASTEXITCODE -ne 0) {
    Write-Log "Initial deployment failed (exit code: $LASTEXITCODE)" 'ERROR'
    exit 1
}
Write-Host ''
Write-Log 'Initial deployment complete.' 'SUCCESS'

# ==============================================================================
#  STEP 6 - Create Scheduled Task in root Task Scheduler Library
# ==============================================================================
Write-Step 6 $TotalSteps "Registering Scheduled Task in root: '$TaskName'..."
try {
    # Remove existing task if present (clean re-register)
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Removed existing task: $TaskName" 'INFO'
    }

    $taskAction = New-ScheduledTaskAction `
        -Execute 'PowerShell.exe' `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TargetScript`""

    # Weekly trigger - every Sunday at 02:00 AM
    $taskTrigger = New-ScheduledTaskTrigger `
        -Weekly `
        -WeeksInterval 1 `
        -DaysOfWeek Sunday `
        -At '02:00'

    $taskSettings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5) `
        -RunOnlyIfNetworkAvailable:$false

    $taskPrincipal = New-ScheduledTaskPrincipal `
        -UserId 'NT AUTHORITY\SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    # No -TaskPath = task goes to root Task Scheduler Library
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $taskPrincipal `
        -Description $TaskDesc `
        -Force | Out-Null

    $task     = Get-ScheduledTask -TaskName $TaskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName

    Write-Log "Task created : $TaskName" 'SUCCESS'
    Write-Log 'Task folder  : Root (Task Scheduler Library)' 'INFO'
    Write-Log "Next run     : $($taskInfo.NextRunTime)" 'INFO'
    Write-Log "State        : $($task.State)" 'INFO'

} catch {
    Write-Log "Failed to create scheduled task: $_" 'ERROR'
    exit 1
}

# ==============================================================================
#  STEP 7 - Final summary
# ==============================================================================
Write-Step 7 $TotalSteps 'Printing final status summary...'

$taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue

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
Write-Host '  Scheduled Task (Task Scheduler Library):' -ForegroundColor Yellow
Write-Host ''
Write-Host "    $TaskName"
Write-Host '       Trigger : Every Sunday at 02:00 AM'
Write-Host '       Folder  : Root (Task Scheduler Library)'
if ($taskInfo) {
    Write-Host "       Next run: $($taskInfo.NextRunTime)"
}
Write-Host '       Runs as : NT AUTHORITY\SYSTEM'
Write-Host ''
Write-Host '  Manage task:'
Write-Host "    Start-ScheduledTask  -TaskName '$TaskName'"
Write-Host "    Stop-ScheduledTask   -TaskName '$TaskName'"
Write-Host "    Get-ScheduledTask    -TaskName '$TaskName'"
Write-Host ''
Write-Host '  Remove setup completely:'
Write-Host "    Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host "    Remove-Item -Recurse -Force '$ScriptsDir'"
Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Powered by Zoos Global  |  Datadog Premium Partner' -ForegroundColor Cyan
Write-Host '  www.zoosglobal.com  |  shivam.anand@zoosglobal.com' -ForegroundColor Cyan
Write-Host "  (c) $(Get-Date -Format yyyy) Zoos Global. All rights reserved." -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ''