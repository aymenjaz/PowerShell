
## 🧼 Windows Maintenance PowerShell Cheat Sheet

### 📌 1. Create a Restore Point

```powershell
Checkpoint-Computer -Description "Weekly Maintanence" -RestorePointType "MODIFY_SETTINGS"
Write-Host "System Restore Point created successfully"
```

---

### 🗑️ 2. Delete Temporary Files

```powershell
# Get Temp folder paths
$objShell = New-Object -ComObject Shell.Application
$objFolder = $objShell.Namespace(0xA)

$temp = Get-ChildItem "env:\TEMP"
$temp2 = $temp.Value
$WinTemp = "C:\Windows\Temp\*"

# Delete user temp files
Write-Host "Removing Junk files in $temp2." -ForegroundColor Magenta
Remove-Item -Recurse "$temp2\*" -Force -Verbose

# Delete Windows temp files
Write-Host "Removing Junk files in $WinTemp." -ForegroundColor Green
Remove-Item -Recurse $WinTemp -Force
```

---

### 🧽 3. Run Disk Cleanup Tool

```powershell
Write-Host "Running Windows disk Clean up Tool" -ForegroundColor Cyan
cleanmgr /sagerun:1 | Out-Null
```

---

### 🔔 4. Notification Beeps + Sleep

```powershell
$([char]7)
Start-Sleep -Seconds 1
$([char]7)
Start-Sleep -Seconds 1

Write-Host "Clean Up Task completed!"
```

---

### 🔁 5. Reboot the Computer

```powershell
Restart-Computer
# NOTE: Syncro or certain environments may not allow reboot via script.
```

---
