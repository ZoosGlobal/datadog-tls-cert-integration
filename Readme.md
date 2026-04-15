# Zoos Global TLS Certificate Monitor

<div align="center">

<img src="https://media.licdn.com/dms/image/v2/C510BAQEaNQXhD4EVaQ/company-logo_200_200/company-logo_200_200/0/1631395395675/zoos_logo?e=2147483647&v=beta&t=OR7jdri2KV5dJZuY7I8bt0U5wOFT6-ElaMb_0Kydvj8" alt="Zoos Global" width="90" height="90"/>
&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://partners.datadoghq.com/resource/1742314164000/PRM_Assets/images/partnerlogo/datadog_partner_premier.png" alt="Datadog Premier Partner" height="90"/>

<br/>

![Version](https://img.shields.io/badge/version-2.0.0-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Windows%20Server-0078D4?style=for-the-badge&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-TLS%20Check-632CA6?style=for-the-badge&logo=datadog&logoColor=white)
![Partner](https://img.shields.io/badge/Datadog-Premium%20Partner-632CA6?style=for-the-badge&logo=datadog&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Status](https://img.shields.io/badge/status-Production%20Ready-brightgreen?style=for-the-badge)

<br/>

**PowerShell → Windows Cert Store → Datadog TLS Check → conf.yaml → Dashboards & Alerts**

*Automatically scans Windows Certificate Stores (Personal, Root, CA), exports certificates,  
generates Datadog TLS conf.yaml, and restarts the Agent — triggered instantly on cert install  
via Windows Event ID 1006, with a weekly fallback every Sunday at 02:00 AM.*

<br/>

![Stores](https://img.shields.io/badge/stores-Personal%20%7C%20Root%20%7C%20CA-blue?style=flat-square)
![Trigger](https://img.shields.io/badge/trigger-Event--Driven%20%2B%20Weekly-blue?style=flat-square)
![Coverage](https://img.shields.io/badge/coverage-All%20LocalMachine%20Stores-blue?style=flat-square)
![Report](https://img.shields.io/badge/report-HTML%20Inventory%20per%20Run-blue?style=flat-square)

</div>

---

## 📁 Directory Structure

```text
C:\scripts\TLSMonitor\
├── setup.ps1                   # One-click setup: first run + registers both scheduled tasks
├── Deploy-TLSMonitor.ps1       # Main engine: scan → export → conf.yaml → agent restart
├── certs\                      # Exported .cer files per store (auto-created)
│   ├── LocalMachine_My\
│   ├── LocalMachine_Root\
│   └── LocalMachine_CA\
├── logs\                       # Per-run log files (auto-created)
└── reports\                    # HTML certificate inventory reports (auto-created)

README.md                       # This file
```

---

## ⚙️ How It Works

```text
Any cert installed on host
        │
        ▼
Windows Event ID 1006 fires
        │
        ▼
Event-driven Scheduled Task triggers (within 30 seconds)
        │
        ▼
Deploy-TLSMonitor.ps1 runs
  ├── Scans Cert:\LocalMachine\My, \Root, \CA
  ├── Exports each cert as .cer file
  ├── Generates Datadog conf.d\tls.d\conf.yaml
  ├── Restarts Datadog Agent
  ├── Validates with: agent check tls
  └── Writes HTML inventory report
        │
        ▼
Datadog Agent reads conf.yaml → TLS Check → Metrics & Monitors
```

> **Weekly fallback** runs every Sunday at 02:00 AM — catches any certificates that were  
> installed silently or missed by the event trigger.

---

## 📊 Datadog TLS Check — What Gets Tracked

Each certificate in `conf.yaml` generates the following Datadog TLS metrics per instance:

| Metric | Description |
|--------|-------------|
| `tls.days_left` | Days until certificate expiry — triggers Warning / Critical thresholds |
| `tls.seconds_left` | Seconds until expiry (raw value for dashboards) |
| `tls.responded` | Agent successfully read the cert `1=yes 0=no` |
| `tls.version` | TLS version detected against `allowed_versions` |
| `tls.cert.valid` | Certificate valid flag `1=valid 0=invalid/expired` |
| `tls.cert.expiry_date` | Expiry date tag for filtering in Datadog |

**Tags applied to every instance:**

| Tag | Value | Purpose |
|-----|-------|---------|
| `cert_store` | `LocalMachine_My` / `LocalMachine_Root` / `LocalMachine_CA` | Store source |
| `host` | Hostname | Per-server filtering |
| `org` | `zoosglobal` | Organisation label |
| `team` | `infra-monitoring` | Team attribution |
| `env` | `prod` | Environment tag |
| `source` | `windows_cert_store` | Origin identifier |
| `managed_by` | `zoosglobal_tls_monitor` | Ownership label |

---

## ⚙️ System Requirements

| Requirement | Version |
|-------------|---------|
| Windows Server | 2016 / 2019 / 2022 / 2025 |
| Datadog Agent | v7+ (TLS Check built-in) |
| PowerShell | 5.1+ |
| Privileges | Administrator / SYSTEM |
| Disk Space | ~50 MB for exported certs + logs |

---

## 1️⃣ Install Datadog Agent

```powershell
# Download installer
Invoke-WebRequest `
  -Uri     "https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi" `
  -OutFile "C:\ddagent.msi"

# Install with your API key
Start-Process -Wait msiexec `
  -ArgumentList '/qn /i C:\ddagent.msi APIKEY="<your_api_key>"'
```

**Verify Agent is running:**

```powershell
Get-Service -Name "datadogagent"
# Expected: Status = Running
```

**Verify TLS check is available:**

```powershell
& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" check tls
```

---

## 2️⃣ One-Click Setup (Recommended)

> Run as **Administrator** from the folder containing both scripts.

```powershell
PowerShell.exe -ExecutionPolicy Bypass -File .\setup.ps1
```

`setup.ps1` performs 9 steps automatically:

```text
[1/9]  Validate Datadog Agent is installed and running
[2/9]  Create C:\scripts\TLSMonitor directory structure
[3/9]  Copy Deploy-TLSMonitor.ps1 to destination
[4/9]  Unblock scripts (remove Zone.Identifier)
[5/9]  Enable Windows Certificate Lifecycle event log
[6/9]  Run Deploy-TLSMonitor.ps1 immediately (first run)
[7/9]  Register EVENT-DRIVEN task (fires on cert install — Event ID 1006)
[8/9]  Register FALLBACK task (every Sunday at 02:00 AM)
[9/9]  Verify both tasks and print final summary
```

**Tasks registered under Task Scheduler → `\ZoosGlobal\`:**

| Task | Trigger | Purpose |
|------|---------|---------|
| `ZoosGlobal-TLS-CertInstall-Trigger` | Windows Event ID 1006 + 30s delay | Fires the instant a cert is installed |
| `ZoosGlobal-TLS-Weekly-Fallback` | Every Sunday at 02:00 AM | Safety net for missed certs |

---

## 3️⃣ Manual Validation

> Test manually **before** relying on the scheduled tasks.

```powershell
# Dry run — scans and generates conf.yaml, skips agent restart
PowerShell.exe -ExecutionPolicy Bypass -File `
  "C:\scripts\TLSMonitor\Deploy-TLSMonitor.ps1" -DryRun

# Live run — full deployment with agent restart
PowerShell.exe -ExecutionPolicy Bypass -File `
  "C:\scripts\TLSMonitor\Deploy-TLSMonitor.ps1"
```

**Expected output:**

```text
══════════════════════════════════════════════════════════════════════
  ZOOS GLOBAL -- Datadog TLS Certificate Monitor
  Version  : 2.0.0
══════════════════════════════════════════════════════════════════════

  [1/5] Validating Datadog Agent...
  ----------------------------------------------------------
  [ OK ] Datadog Agent is running  (Status: Running)
  [ .. ] Agent version : Datadog Agent 7.x.x

  [2/5] Backing up existing conf.yaml...
  ----------------------------------------------------------
  [ OK ] Backup created : C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml.bak_20260415_180000

  [3/5] Scanning Windows Certificate Stores...
  ----------------------------------------------------------
  [ OK ] LocalMachine_My   — 12 cert(s)
  [ OK ] LocalMachine_Root — 45 cert(s)
  [ OK ] LocalMachine_CA   — 38 cert(s)
  [ OK ] Scan complete — Exported: 95 | Skipped: 0

  [4/5] Generating conf.yaml (95 instances)...
  ----------------------------------------------------------
  [ OK ] conf.yaml written : C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml

  [5/5] Deploying to Datadog Agent...
  ----------------------------------------------------------
  [ OK ] Agent restarted successfully.
  [ OK ] Validation — OK: 95 | ERROR: 0
  [ OK ] HTML report : C:\scripts\TLSMonitor\reports\TLSReport_SERVER01_20260415_180000.html
```

**Verify in Datadog:**  
Metrics → Explorer → search `tls.days_left`

---

## 4️⃣ Windows Task Scheduler (Manual)

<details>
<summary>Click to expand — PowerShell method</summary>

```powershell
$action = New-ScheduledTaskAction `
  -Execute  'PowerShell.exe' `
  -Argument '-NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\scripts\TLSMonitor\Deploy-TLSMonitor.ps1"'

$trigger = New-ScheduledTaskTrigger `
  -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At '02:00'

$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit    (New-TimeSpan -Hours 1) `
  -MultipleInstances     IgnoreNew `
  -StartWhenAvailable `
  -RestartCount          3 `
  -RestartInterval       (New-TimeSpan -Minutes 5)

$principal = New-ScheduledTaskPrincipal `
  -UserId    'NT AUTHORITY\SYSTEM' `
  -RunLevel  Highest `
  -LogonType ServiceAccount

Register-ScheduledTask `
  -TaskName    'ZoosGlobal-TLS-Weekly-Fallback' `
  -TaskPath    '\ZoosGlobal' `
  -Action      $action `
  -Trigger     $trigger `
  -Settings    $settings `
  -Principal   $principal `
  -Force
```

</details>

---

## 5️⃣ Execution Timeline

```text
Cert installed on host
  │
  ├── Event ID 1006 fires
  │     └── 30s delay → Deploy-TLSMonitor.ps1 runs
  │           ├── Scan  : LocalMachine\My, \Root, \CA
  │           ├── Export: .cer files to C:\scripts\TLSMonitor\certs\
  │           ├── Write : conf.d\tls.d\conf.yaml (all instances)
  │           ├── Restart: datadogagent service
  │           ├── Validate: agent check tls
  │           └── Report: HTML inventory → C:\scripts\TLSMonitor\reports\
  │
  └── Datadog Agent reads updated conf.yaml → emits tls.days_left per cert

Every Sunday 02:00 AM (fallback)
  └── Deploy-TLSMonitor.ps1 runs (same steps as above)
```

---

## 6️⃣ Pre-built Datadog Monitors

### 🔴 Certificate Expiry — Critical

```text
Query    : min(last_5m):min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host,instance} < 14
Critical : < 14 days
Message  : 🔴 Certificate expiring in {{value}} days on {{host.name}}
           Instance: {{instance.name}} — renew immediately.
```

### ⚠️ Certificate Expiry — Warning

```text
Query   : min(last_5m):min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host,instance} < 30
Warning : < 30 days
Message : ⚠️ Certificate expiring in {{value}} days on {{host.name}}
          Instance: {{instance.name}} — schedule renewal.
```

### 🔴 Certificate Not Responding

```text
Query   : max(last_5m):min:tls.responded{managed_by:zoosglobal_tls_monitor} by {host,instance} < 1
Alert   : < 1
Message : 🔴 TLS check failed on {{host.name}} — {{instance.name}} is not responding.
          Check cert file path or Datadog Agent status.
```

### ⚠️ TLS Version Mismatch

```text
Query   : max(last_5m):max:tls.version{managed_by:zoosglobal_tls_monitor} by {host,instance} < 2
Alert   : < 2  (TLSv1.0 or TLSv1.1 detected)
Message : ⚠️ Insecure TLS version detected on {{host.name}} — {{instance.name}}.
          Only TLSv1.2 and TLSv1.3 are permitted.
```

---

## 7️⃣ Datadog Dashboard Queries

| Widget | Query |
|--------|-------|
| Minimum days left across all certs | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host}` |
| Days left per cert (table) | `min:tls.days_left{*} by {host,instance,cert_store}` |
| Certs expiring within 30 days | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {instance}` (threshold: 30) |
| Certs not responding | `min:tls.responded{managed_by:zoosglobal_tls_monitor} by {host,instance}` |
| Cert count per store | `count:tls.days_left{*} by {cert_store}` |
| TLS version compliance | `avg:tls.version{managed_by:zoosglobal_tls_monitor} by {host,instance}` |
| Expired certs (days_left < 0) | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {instance}` (threshold: 0) |
| Per-host cert health | `min:tls.days_left{*} by {host}` |

---

## 🛡️ Production Features

| Feature | Status |
|---------|--------|
| Scans `Cert:\LocalMachine\My` (Personal) | ✅ |
| Scans `Cert:\LocalMachine\Root` (Trusted Root CAs) | ✅ |
| Scans `Cert:\LocalMachine\CA` (Intermediate CAs) | ✅ |
| Exports each cert as `.cer` file | ✅ |
| Auto-generates `conf.d\tls.d\conf.yaml` | ✅ |
| Backs up existing conf.yaml before overwrite | ✅ |
| Rollback on agent restart failure | ✅ |
| Event-driven trigger — instant on cert install (Event ID 1006) | ✅ |
| Weekly fallback task — every Sunday at 02:00 AM | ✅ |
| Datadog Agent validation via `agent check tls` | ✅ |
| Per-cert Datadog tags (store, host, org, env, team) | ✅ |
| Warning threshold: 30 days | ✅ |
| Critical threshold: 14 days | ✅ |
| HTML inventory report per run | ✅ |
| Color-coded expiry status (green / amber / red) | ✅ |
| Per-run log file with timestamps | ✅ |
| Dry-run mode (`-DryRun`) — no agent restart | ✅ |
| SYSTEM scheduler compatible | ✅ |
| Graceful skip on empty stores | ✅ |
| Duplicate cert protection (thumbprint-based naming) | ✅ |

---

## ✅ Production Checklist

- [ ] Datadog Agent installed and running on target host
- [ ] `setup.ps1` run as Administrator
- [ ] Both scheduled tasks visible in Task Scheduler → `\ZoosGlobal\`
- [ ] `conf.d\tls.d\conf.yaml` created with correct instances
- [ ] `agent check tls` passes with 0 errors
- [ ] `tls.days_left` metrics visible in Datadog Metrics Explorer
- [ ] Expiring certs reviewed with team
- [ ] Monitor created for Critical expiry (< 14 days)
- [ ] Monitor created for Warning expiry (< 30 days)
- [ ] Monitor created for cert not responding
- [ ] HTML report in `C:\scripts\TLSMonitor\reports\` reviewed
- [ ] Log file in `C:\scripts\TLSMonitor\logs\` reviewed

---

## 🚨 Troubleshooting

| Issue | Fix |
|-------|-----|
| `tls.days_left` not appearing in Datadog | Run `agent check tls` — check for errors in output |
| `conf.yaml` not generated | Ensure `Cert:\LocalMachine\My` has at least one cert; check log file |
| Agent restart failed | Check Windows Event Log → Application → `datadogagent`; rollback is automatic |
| Event task not firing | Verify cert lifecycle log is enabled: `wevtutil qe Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational` |
| `[WARN] Cannot access store` | Ensure script runs as SYSTEM or Administrator |
| Scheduled task not running | Run: `schtasks /query /tn "ZoosGlobal-TLS-CertInstall-Trigger" /fo LIST /v` |
| Certs showing as expired | Expected for old root/intermediate CAs — filter in Datadog by `cert_store:LocalMachine_My` |
| `ExecutionPolicy` error | Run: `Set-ExecutionPolicy -Scope LocalMachine RemoteSigned` |
| Old conf.yaml not updated | Manually trigger: `Start-ScheduledTask -TaskName 'ZoosGlobal-TLS-CertInstall-Trigger' -TaskPath '\ZoosGlobal'` |

---

## 🔧 Manage Tasks

```powershell
# Trigger manually
Start-ScheduledTask -TaskName 'ZoosGlobal-TLS-CertInstall-Trigger' -TaskPath '\ZoosGlobal'
Start-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'     -TaskPath '\ZoosGlobal'

# Check status
Get-ScheduledTask -TaskPath '\ZoosGlobal' | Format-Table TaskName, State

# View last run result
Get-ScheduledTaskInfo -TaskName 'ZoosGlobal-TLS-Weekly-Fallback' -TaskPath '\ZoosGlobal'

# Remove everything
Unregister-ScheduledTask -TaskName 'ZoosGlobal-TLS-CertInstall-Trigger' -TaskPath '\ZoosGlobal' -Confirm:$false
Unregister-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'     -TaskPath '\ZoosGlobal' -Confirm:$false
Remove-Item -Recurse -Force 'C:\scripts\TLSMonitor'
```

---

## 👤 Author

| | |
|--|--|
| **Name** | Shivam Anand |
| **Title** | Sr. DevOps Engineer \| Engineering |
| **Organisation** | Zoos Global |
| **Email** | [shivam.anand@zoosglobal.com](mailto:shivam.anand@zoosglobal.com) |
| **Web** | [www.zoosglobal.com](https://www.zoosglobal.com) |
| **Address** | Violena, Pali Hill, Bandra West, Mumbai - 400050 |

---

<div align="center">

<img src="https://media.licdn.com/dms/image/v2/C510BAQEaNQXhD4EVaQ/company-logo_200_200/company-logo_200_200/0/1631395395675/zoos_logo?e=2147483647&v=beta&t=OR7jdri2KV5dJZuY7I8bt0U5wOFT6-ElaMb_0Kydvj8" alt="Zoos Global" width="60" height="60"/>
&nbsp;&nbsp;
<img src="https://partners.datadoghq.com/resource/1742314164000/PRM_Assets/images/partnerlogo/datadog_partner_premier.png" alt="Datadog Premier Partner" height="60"/>

<br/><br/>

**Version 2.0.0 · Last Updated: April 15, 2026**

© 2026 Zoos Global · <a href="LICENSE">MIT License</a>
</div>