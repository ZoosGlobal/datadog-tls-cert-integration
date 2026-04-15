# Zoos Global TLS Certificate Monitor

<div align="center">

<img src="https://media.licdn.com/dms/image/v2/C510BAQEaNQXhD4EVaQ/company-logo_200_200/company-logo_200_200/0/1631395395675/zoos_logo?e=2147483647&v=beta&t=OR7jdri2KV5dJZuY7I8bt0U5wOFT6-ElaMb_0Kydvj8" alt="Zoos Global" width="90" height="90"/>
&nbsp;&nbsp;&nbsp;&nbsp;
<img src="https://partners.datadoghq.com/resource/1742314164000/PRM_Assets/images/partnerlogo/datadog_partner_premier.png" alt="Datadog Premier Partner" height="90"/>

<br/>

![Version](https://img.shields.io/badge/version-2.1.0-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Windows%20Server-0078D4?style=for-the-badge&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Datadog](https://img.shields.io/badge/Datadog-TLS%20Check-632CA6?style=for-the-badge&logo=datadog&logoColor=white)
![Partner](https://img.shields.io/badge/Datadog-Premium%20Partner-632CA6?style=for-the-badge&logo=datadog&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Status](https://img.shields.io/badge/status-Production%20Ready-brightgreen?style=for-the-badge)

<br/>

**PowerShell → Windows Cert Store → Datadog TLS Check → conf.yaml → Dashboards & Alerts**

*Automatically scans Windows Certificate Stores (Personal, Root, CA), exports certificates,  
generates Datadog TLS conf.yaml, and restarts the Agent — with a weekly fallback every Sunday at 02:00 AM.*

<br/>

![Stores](https://img.shields.io/badge/stores-Personal%20%7C%20Root%20%7C%20CA-blue?style=flat-square)
![Trigger](https://img.shields.io/badge/trigger-Weekly%20Sunday%2002%3A00-blue?style=flat-square)
![Coverage](https://img.shields.io/badge/coverage-All%20LocalMachine%20Stores-blue?style=flat-square)
![Report](https://img.shields.io/badge/report-Text%20Inventory%20per%20Run-blue?style=flat-square)

</div>

---

## 📁 Directory Structure

```text
C:\scripts\TLSMonitor\
├── Deploy-TLSMonitor.ps1       # Main engine: scan → export → conf.yaml → agent restart
├── certs\                      # Exported .cer files per store (auto-created)
│   ├── LocalMachine_My\
│   ├── LocalMachine_Root\
│   └── LocalMachine_CA\
├── logs\                       # Per-run log files (auto-created)
└── reports\                    # Text certificate inventory reports (auto-created)

setup.ps1                       # One-click setup: first run + registers weekly scheduled task
README.md                       # This file
```

---

## ⚙️ How It Works

```text
setup.ps1 runs once (as Administrator)
        │
        ▼
Deploy-TLSMonitor.ps1 copied to C:\scripts\TLSMonitor\
        │
        ▼
Initial deployment runs immediately
  ├── Scans Cert:\LocalMachine\My, \Root, \CA
  ├── Exports each cert as .cer file
  ├── Generates Datadog conf.d\tls.d\conf.yaml
  ├── Restarts Datadog Agent
  ├── Validates with: agent check tls
  └── Writes text inventory report
        │
        ▼
Weekly Scheduled Task registered in Task Scheduler Library (root)
  └── Fires every Sunday at 02:00 AM as NT AUTHORITY\SYSTEM
        │
        ▼
Datadog Agent reads conf.yaml → TLS Check → Metrics & Monitors
```

> **Note:** The task is created in the **root Task Scheduler Library** (no custom subfolder).  
> This avoids event-trigger type mismatch issues present on some Windows Server versions.

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

`setup.ps1` performs **7 steps** automatically:

```text
[1/7]  Validate Datadog Agent is installed and running
[2/7]  Create C:\scripts\TLSMonitor directory structure
[3/7]  Copy Deploy-TLSMonitor.ps1 to destination
[4/7]  Unblock scripts (remove Zone.Identifier)
[5/7]  Run Deploy-TLSMonitor.ps1 immediately (first run)
[6/7]  Register WEEKLY task in root Task Scheduler Library (Sunday 02:00 AM)
[7/7]  Print final status summary
```

**Task registered in Task Scheduler Library (root):**

| Task | Trigger | Folder |
|------|---------|--------|
| `ZoosGlobal-TLS-Weekly-Fallback` | Every Sunday at 02:00 AM | Root (Task Scheduler Library) |

---

## 3️⃣ Manual Validation

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
======================================================================
  ZOOS GLOBAL -- Datadog TLS Certificate Monitor
  Version  : 2.1.0
======================================================================

  [1/6] Validating prerequisites...
  [ OK ] Datadog Agent is running (Status: Running)
  [ .. ] Agent version : Agent 7.x.x

  [2/6] Backing up existing conf.yaml...
  [ OK ] Backup created : C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml.bak_20260415_020000

  [3/6] Scanning Windows Certificate Stores...
  [WARN] Store LocalMachine_My - 0 certs
  [ OK ] Store LocalMachine_Root - 29 cert(s)
  [ OK ] Store LocalMachine_CA - 3 cert(s)
  [ OK ] Scan complete - Exported: 32 | Skipped: 0

  [4/6] Generating conf.yaml (32 instances)...
  [ OK ] conf.yaml written : C:\ProgramData\Datadog\conf.d\tls.d\conf.yaml

  [5/6] Deploying to Datadog Agent...
  [ OK ] Agent restarted successfully.
  [ OK ] Validation - OK: 32 | ERROR: 0

  [6/6] Generating report and summary...
  [ OK ] Text report : C:\scripts\TLSMonitor\reports\TLSReport_SERVER01_20260415_020000.txt
```

**Verify in Datadog:**  
Metrics → Explorer → search `tls.days_left`

---

## 4️⃣ Execution Timeline

```text
setup.ps1 runs once
  └── Deploy-TLSMonitor.ps1 runs immediately (first deployment)
        ├── Scan  : LocalMachine\My, \Root, \CA
        ├── Export: .cer files to C:\scripts\TLSMonitor\certs\
        ├── Write : conf.d\tls.d\conf.yaml (all instances)
        ├── Restart: datadogagent service
        ├── Validate: agent check tls
        └── Report: text inventory → C:\scripts\TLSMonitor\reports\

Every Sunday 02:00 AM (weekly task in Task Scheduler Library root)
  └── Deploy-TLSMonitor.ps1 runs automatically (same steps as above)

Datadog Agent reads updated conf.yaml → emits tls.days_left per cert
```

---

## 5️⃣ Pre-built Datadog Monitors

### 🔴 Certificate Expiry — Critical

```text
Query    : min(last_5m):min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host,instance} < 14
Critical : < 14 days
Message  : Certificate expiring in {{value}} days on {{host.name}}
           Instance: {{instance.name}} -- renew immediately.
```

### ⚠️ Certificate Expiry — Warning

```text
Query   : min(last_5m):min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host,instance} < 30
Warning : < 30 days
Message : Certificate expiring in {{value}} days on {{host.name}}
          Instance: {{instance.name}} -- schedule renewal.
```

### 🔴 Certificate Not Responding

```text
Query   : max(last_5m):min:tls.responded{managed_by:zoosglobal_tls_monitor} by {host,instance} < 1
Alert   : < 1
Message : TLS check failed on {{host.name}} -- {{instance.name}} is not responding.
```

### ⚠️ TLS Version Mismatch

```text
Query   : max(last_5m):max:tls.version{managed_by:zoosglobal_tls_monitor} by {host,instance} < 2
Alert   : < 2  (TLSv1.0 or TLSv1.1 detected)
Message : Insecure TLS version on {{host.name}} -- only TLSv1.2 and TLSv1.3 permitted.
```

---

## 6️⃣ Datadog Dashboard Queries

| Widget | Query |
|--------|-------|
| Minimum days left across all certs | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {host}` |
| Days left per cert (table) | `min:tls.days_left{*} by {host,instance,cert_store}` |
| Certs expiring within 30 days | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {instance}` |
| Certs not responding | `min:tls.responded{managed_by:zoosglobal_tls_monitor} by {host,instance}` |
| Cert count per store | `count:tls.days_left{*} by {cert_store}` |
| TLS version compliance | `avg:tls.version{managed_by:zoosglobal_tls_monitor} by {host,instance}` |
| Expired certs (days_left < 0) | `min:tls.days_left{managed_by:zoosglobal_tls_monitor} by {instance}` |
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
| Weekly Scheduled Task in root Task Scheduler Library | ✅ |
| Fires every Sunday at 02:00 AM as NT AUTHORITY\SYSTEM | ✅ |
| Datadog Agent validation via `agent check tls` | ✅ |
| Per-cert Datadog tags (store, host, org, source) | ✅ |
| Warning threshold: 30 days | ✅ |
| Critical threshold: 14 days | ✅ |
| Plain text inventory report per run | ✅ |
| Per-run log file with timestamps | ✅ |
| Dry-run mode (`-DryRun`) -- no agent restart | ✅ |
| SYSTEM scheduler compatible | ✅ |
| Graceful skip on empty stores | ✅ |
| Duplicate cert protection (thumbprint-based naming) | ✅ |
| ASCII-safe -- no encoding issues on any Windows codepage | ✅ |

---

## ✅ Production Checklist

- [ ] Datadog Agent installed and running on target host
- [ ] `setup.ps1` run as Administrator: `PowerShell.exe -ExecutionPolicy Bypass -File .\setup.ps1`
- [ ] Scheduled task visible in Task Scheduler Library (root): `ZoosGlobal-TLS-Weekly-Fallback`
- [ ] `conf.d\tls.d\conf.yaml` created with correct instances
- [ ] `agent check tls` passes with 0 errors
- [ ] `tls.days_left` metrics visible in Datadog Metrics Explorer
- [ ] Expiring certs reviewed with team
- [ ] Monitor created for Critical expiry (< 14 days)
- [ ] Monitor created for Warning expiry (< 30 days)
- [ ] Monitor created for cert not responding
- [ ] Text report in `C:\scripts\TLSMonitor\reports\` reviewed
- [ ] Log file in `C:\scripts\TLSMonitor\logs\` reviewed

---

## 🚨 Troubleshooting

| Issue | Fix |
|-------|-----|
| `ExecutionPolicy` error | Run: `PowerShell.exe -ExecutionPolicy Bypass -File .\setup.ps1` |
| `tls.days_left` not in Datadog | Run `agent check tls` -- check output for errors |
| `conf.yaml` not generated | Check stores have certs; check log file |
| Agent restart failed | Check Event Log → Application → `datadogagent`; rollback is automatic |
| `[WARN] Cannot access store` | Ensure script runs as Administrator or SYSTEM |
| Scheduled task not running | Run: `Get-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'` |
| Certs showing as expired | Expected for old root/intermediate CAs -- filter by `cert_store:LocalMachine_My` |
| conf.yaml not updated | Manually trigger: `Start-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'` |

---

## 🔧 Manage Task

```powershell
# Trigger manually
Start-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'

# Check status
Get-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'

# View last run result
Get-ScheduledTaskInfo -TaskName 'ZoosGlobal-TLS-Weekly-Fallback'

# Remove everything
Unregister-ScheduledTask -TaskName 'ZoosGlobal-TLS-Weekly-Fallback' -Confirm:$false
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

**Version 2.1.0 · Last Updated: April 15, 2026**

© 2026 Zoos Global · <a href="LICENSE">MIT License</a>

</div>