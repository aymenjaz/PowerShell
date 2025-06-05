
# 🧠 Active Directory Replication PowerShell Cheat Sheet

> Useful commands to **check**, **troubleshoot**, and **force** Active Directory replication using PowerShell and CMD.

---

## 🔍 Check Domain Controller Health

```cmd
dcdiag /s:ABCP-DC
```

---

## 🔁 Check Replication Failures

### 🔹 For a specific Domain Controller

```powershell
Get-ADReplicationFailure -Target ABCP-DC.abcponline.com
```

### 🔹 For all Domain Controllers in a Domain

```powershell
Get-ADReplicationFailure -Target abcponline.com -Scope Domain
```

### 🔹 For the entire Forest

```powershell
Get-ADReplicationFailure -Target rebeladmin.com -Scope Forest
```

### 🔹 For a specific AD Site

```powershell
Get-ADReplicationFailure -Target LondonSite -Scope Site
```

---

## 📊 View Replication Metadata

### 🔹 For a specific Domain Controller

```powershell
Get-ADReplicationPartnerMetadata -Target ABCP-DC.abcponline.com
```

### 🔹 For all Domain Controllers in the Domain

```powershell
Get-ADReplicationPartnerMetadata -Target "abcponline.com" -Scope Domain
```

### 🔹 View last successful replication

```powershell
Get-ADReplicationPartnerMetadata -Target "abcponline.com" -Scope Domain | Select-Object Server, LastReplicationSuccess
```

### 🔹 Check current replication queue

```powershell
Get-ADReplicationQueueOperation ABCP-DC.abcponline.com
```

---

## 🌐 View AD Topology Info

```powershell
Get-ADReplicationSite -Filter *
Get-ADReplicationConnection
```

---

## 🔄 Force Replication

### 🔹 CMD: Sync all partitions between all DCs

```cmd
repadmin /syncall /AdeP
```

### 🔹 PowerShell: Force replication for all Domain Controllers

```powershell
(Get-ADDomainController -Filter *).Name | ForEach-Object {
    repadmin /syncall $_ (Get-ADDomain).DistinguishedName /AdeP
}
```

---

## ⚡ Full Automation: Force Replication Across All DCs & Sites

```powershell
function ReplicateAllDomainController {
    (Get-ADDomainController -Filter *).Name | ForEach-Object {
        repadmin /syncall $_ (Get-ADDomain).DistinguishedName /e /A | Out-Null
    }
    Start-Sleep 10
    Get-ADReplicationPartnerMetadata -Target "$env:userdnsdomain" -Scope Domain |
        Select-Object Server, LastReplicationSuccess
}

ReplicateAllDomainController
```

---

## 📎 Requirements

* **RSAT Tools** must be installed
* Must run **PowerShell as Administrator**
* Compatible with **Windows Server** and **Windows 10/11** with AD RSAT module


