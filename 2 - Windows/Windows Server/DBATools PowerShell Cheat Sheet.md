

## 🛠️ **DBATools PowerShell Cheat Sheet**

### 🔐 Set Execution Policy

```powershell
Set-ExecutionPolicy RemoteSigned
```

---

### 📦 Install & Import dbatools Module

```powershell
# Install dbatools if not available
IF (-not (Get-Module -Name dbatools -ListAvailable)) {
    Write-Host "BEGIN - Install dbatools Module " -ForegroundColor Yellow
    Install-Module -Name dbatools -Force -AllowClobber
    Write-Host "Module dbatools Installed Successfully .......................... OK" -ForegroundColor Green
}

# Import the module
Import-Module -Name dbatools -Force
```

---

### 🔑 Reset SQL Admin Password

```powershell
# Reset password for the 'sa' account
Reset-DbaAdmin -SqlInstance "Localhost\SQLEXPRESS" -SqlCredential sa -Force -Confirm:$false
```

---

### 🗃️ List Databases

```powershell
# List all databases (excluding system DBs)
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" -ExcludeDatabase model,master,tempdb,msdb

# List names and last full backups
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" | Select Name, LastFullBackup

# Filter by recovery model
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" -RecoveryModel Full, Simple

# List read-only databases
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" -Access ReadOnly
```

---

### 🪞 Create Database Snapshots

```powershell
# Get DB1 database details
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" -Database DB1

# Method 1: Create snapshot from piped output
Get-DbaDatabase -SqlInstance "Localhost\SQLEXPRESS" -Database DB1 | New-DbaDbSnapshot

# Method 2: Create multiple snapshots directly
New-DbaDbSnapshot -SqlInstance "Localhost\SQLEXPRESS" -Database DB1, HR, Accounting

# Method 3: Specify snapshot path
New-DbaDbSnapshot -SqlInstance "Localhost\SQLEXPRESS" -Database DB1, HR, Accounting -Path C:\Snapshots
```

---

