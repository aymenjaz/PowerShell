
# 🧾 PowerShell GUI & Dialog Cheat Sheet

## 📁 Select Folder Dialog

```powershell
Function Select-FolderDialog {
    param([string]$Description = "Select Folder", [string]$RootFolder = "Desktop")
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.RootFolder = $RootFolder
    if ($dialog.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true })) -eq "OK") {
        return $dialog.SelectedPath
    } else { return $null }
}
# Usage:
$dir = Select-FolderDialog
```

---

## 💾 Save File Dialog

```powershell
Add-Type -AssemblyName System.Windows.Forms
$dlg = New-Object System.Windows.Forms.SaveFileDialog
if ($dlg.ShowDialog() -eq 'Ok') {
    Write-Host "You chose to create $($dlg.FileName)"
}
```

---

## 💾 Save File With Extension Filter

```powershell
function SaveFileWindow {
    param(
        [string] $InitialDirectory = "C:\",
        [string] $filter
    )
    Add-Type -AssemblyName System.Windows.Forms
    $InitialDirectory = Convert-Path $InitialDirectory
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Filter = "All files ($filter)|$filter"
    if ($dialog.ShowDialog() -eq 'Ok') { $dialog.FileName }
}
# Usage:
SaveFileWindow -filter *.pdf
```

---

## 📄 Select File By Extension (Filter + Exclude)

```powershell
function Get-FileTypeWindow {
    param(
        [string] $InitialDirectory,
        [string] $Extension,
        [string] $Exclude
    )
    Add-Type -AssemblyName System.Windows.Forms
    $InitialDirectory = Convert-Path $InitialDirectory
    $filter = (Get-ChildItem $InitialDirectory -Filter $Extension |
        Where-Object Name -NotMatch $Exclude).Name -join ';'
    if (-not $filter) { $filter = $Extension }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Filter = "All files ($Extension)|$filter"
    if ($dialog.ShowDialog() -eq 'Ok') { $dialog.FileName }
}
# Usage:
Get-FileTypeWindow "C:\" -Extension *.csv
```

---

## 💬 Message Boxes with Microsoft.VisualBasic

```powershell
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")

# Yes / No
$res = [Microsoft.VisualBasic.Interaction]::MsgBox("Disable Defender?", "YesNo,SystemModal,Question,DefaultButton2", "Confirm")

# Yes / No / Cancel
$res = [Microsoft.VisualBasic.Interaction]::MsgBox("Disable Defender?", "YesNoCancel,SystemModal,Exclamation", "Confirm")

# OK / Cancel
$res = [Microsoft.VisualBasic.Interaction]::MsgBox("Disable Defender?", "OkCancel,SystemModal", "Confirm")

# Abort / Retry / Ignore
$res = [Microsoft.VisualBasic.Interaction]::MsgBox("Disable Defender?", "AbortRetryIgnore,SystemModal,Critical", "Confirm")

# Info Box
$res = [Microsoft.VisualBasic.Interaction]::MsgBox("Info message", "OKOnly,SystemModal,Information", "Info")
```

---

## 💬 WScript.Shell Message Boxes

```powershell
$pop = New-Object -ComObject WScript.Shell
$answer = $pop.Popup("Reboot now?", $seconds_to_wait, "Nightly Reboot", 4)

# Button Style Values:
# 0 = OK Only
# 1 = OK/Cancel
# 2 = Abort/Retry/Ignore
# 3 = Yes/No/Cancel
# 4 = Yes/No
# 5 = Retry/Cancel
```

---

## 💬 Enhanced GUI with PSScriptTools (Install via PSGallery)

```powershell
Import-Module PSScriptTools

# Text Input
$name = Invoke-InputBox -Prompt "Enter username" -Title "User Setup"

# Password Input
Invoke-InputBox -Prompt "Enter password" -AsSecureString -BackgroundColor Red

# Yes/No
$res = New-WPFMessageBox -Message "Continue?" -Title "Confirm" -Icon Question -ButtonSet YesNo

# OK Only with Error Icon
$res = New-WPFMessageBox -Message "Something went wrong!" -Title "Error" -Icon Error -ButtonSet OK

# Custom Buttons
$res = New-WPFMessageBox -Message "Select an option:" -Title "Action" -Background Cornsilk -Icon Warning -CustomButtonSet ([ordered]@{
    "Reboot" = 1
    "Shutdown" = 2
    "Cancel" = 3
})
```

---

## 📊 Visual Progress Bars with PSScriptTools

```powershell
Import-Module PSScriptTools

# Red to Green Gradient Bar
Write-Host "45% " -NoNewline; New-RedGreenGradient -Percent 0.45
Write-Host "75% " -NoNewline; New-RedGreenGradient -Percent 0.75
Write-Host "100% " -NoNewline; New-RedGreenGradient -Percent 1

# ANSI Color Progress Bar
Write-ANSIProgress -PercentComplete 0.75
```


