
# 🔐 BitLocker PowerShell Cheat Sheet

## 📛 Disable BitLocker

```powershell
# Disable BitLocker on C: drive
manage-bde -off C:
```

---

## 🔄 Resume BitLocker Protection

```powershell
# Resume BitLocker protection on C: drive
Resume-BitLocker -MountPoint "C:"
```

---

## ⏸️ Suspend BitLocker and Reboot

```powershell
# Suspend BitLocker protection and reboot once
Suspend-BitLocker -MountPoint "C:" -RebootCount 1
Restart-Computer -Force
```

---

## 📝 Export Recovery Keys to File

```powershell
# Identify BitLocker volumes
$BitlockerVolumes = Get-BitLockerVolume

# Prepare output path
$compname = $env:COMPUTERNAME
$Today = Get-Date -Format "dd.MM.yyyy"
$path = "C:\BLK"

If (!(Test-Path $path)) {
    New-Item -ItemType Directory -Force -Path $path
}

# Export recovery keys to file
$BitlockerVolumes | ForEach-Object {
    $MountPoint = $_.MountPoint
    $RecoveryKey = [string]($_.KeyProtector).RecoveryPassword
    if ($RecoveryKey.Length -gt 5) {
        Write-Output "The drive $MountPoint has a recovery key $RecoveryKey."
    }
} > "$path\$compname-$Today.txt"
```

---

## 🔍 Display Recovery Keys in Console

```powershell
Get-BitLockerVolume | ForEach-Object {
    Write-Output ("Drive " + $_.MountPoint + " key is " + [string]($_.KeyProtector).RecoveryPassword)
}
```

---

## 🔒 Enable BitLocker on New Computer

```powershell
# WARNING: Replace plain-text PIN with a secure method in production environments
$SecureString = ConvertTo-SecureString "YourSecurePin123!" -AsPlainText -Force

Enable-BitLocker -MountPoint "C:" `
                 -EncryptionMethod Aes256 `
                 -UsedSpaceOnly `
                 -Pin $SecureString `
                 -TPMandPinProtector
```

