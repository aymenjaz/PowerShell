
# 💠 AzureAD PowerShell Cheat Sheet

Manage Azure Active Directory (Azure AD) using the `AzureAD` PowerShell module.

---

## 🧰 Install & Import AzureAD Module

```powershell
# Install AzureAD module if not already installed
if (-not (Get-Module -Name AzureAD -ListAvailable)) {
    Write-Host "BEGIN - Install AzureAD Module " -ForegroundColor Green
    Install-Module -Name AzureAD -Force
    Write-Host "Module AzureAD Installed ....................................... OK" -ForegroundColor Green
}

# Check AzureAD module info
Get-Module AzureAD

# Import the AzureAD module
Import-Module AzureAD

# List all available cmdlets in AzureAD module
Get-Command -Module AzureAD
```

---

## 🔐 Connect / Disconnect from AzureAD

```powershell
# Connect to Azure Active Directory
Connect-AzureAD

# Disconnect from Azure Active Directory
Disconnect-AzureAD
```

---

## 👥 Manage Azure AD Users

```powershell
# List all users
Get-AzureADUser

# List all guest users
Get-AzureADUser | Where-Object UserType -eq "Guest"

# Find user(s) with a Display Name that includes 'admin'
Get-AzureADUser | Where-Object DisplayName -like 'admin' | Select-Object *
```

### ➕ Create a New Azure AD User

```powershell
$PWord = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$PWord.Password = "Delta987654"  # Note: Avoid spaces in MailNickName

New-AzureADUser `
  -DisplayName "DataBase Admin" `
  -PasswordProfile $PWord `
  -UserPrincipalName "dba@aymeneljazirioutlook.onmicrosoft.com" `
  -AccountEnabled $true `
  -MailNickName "DBAtest" `
  -UsageLocation "CA"
```

---

## 📂 Manage Azure AD Groups

```powershell
# List all Azure AD groups
Get-AzureADGroup

# Create a new Security Group
New-AzureADGroup `
  -DisplayName "App1Access" `
  -Description "Grant Access to App1" `
  -MailNickName "App1Access" `
  -SecurityEnabled $true `
  -MailEnabled $false
```

### ➕ Add User to Group

```powershell
# Add user to group using Object IDs
Add-AzureADGroupMember `
  -ObjectId "9d75ceb8-ef9f-4543-8d1f-eb230c97e6c2" `
  -RefObjectId "4b4f4a3c-5d4a-42c8-9141-a548bb56b47e"

# Verify group membership
Get-AzureADGroupMember -ObjectId "9d75ceb8-ef9f-4543-8d1f-eb230c97e6c2"
```

---

✅ **Tip**: Use `Select-Object *` with most `Get-AzureAD*` cmdlets to see all available properties.

