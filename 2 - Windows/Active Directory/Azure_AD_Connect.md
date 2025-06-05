
## 🛠️ Azure AD Connect (ADSync) PowerShell Cheat Sheet

> Useful PowerShell commands to manage and troubleshoot Azure AD Connect synchronization.

---

### 📋 Get ADSync Global Settings

```powershell
Import-Module ADSync

(Get-ADSyncGlobalSettings).Parameters | Select-Object Name, Value
```

---

### 🔍 Check Current Sync Scheduler Status

```powershell
Get-ADSyncScheduler
```

---

### ⏸️ Disable Sync Scheduler

```powershell
Set-ADSyncScheduler –SyncCycleEnabled $False
```

---

### ▶️ Enable Sync Scheduler

```powershell
Set-ADSyncScheduler –SyncCycleEnabled $True
```

---

### ⏱️ Change Sync Interval (minimum: 30 minutes)

```powershell
# Example: Set to 40 minutes
Set-ADSyncScheduler –CustomizedSyncCycleInterval 00:40:00
```

> ⚠️ Sync intervals less than 30 minutes are **not supported**.

---

### 🔄 Run a Delta Sync (most common)

```powershell
Start-ADSyncSyncCycle -PolicyType Delta
```

---

### ♻️ Run a Full Sync (less common)

```powershell
Start-ADSyncSyncCycle -PolicyType Initial
```

---

✅ **Pro Tip:**
Use `Delta` syncs for routine updates and `Initial` syncs when major schema or rule changes occur.


