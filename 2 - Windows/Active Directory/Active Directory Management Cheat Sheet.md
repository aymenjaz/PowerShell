
# 🧠 Active Directory Management Cheat Sheet with PowerShell

This PowerShell guide provides a collection of commonly used Active Directory (AD) commands for managing users, groups, and organizational units.
It is intended for IT administrators and system engineers who frequently work with on-premises Active Directory environments.

> ✅ Make sure the `ActiveDirectory` PowerShell module is installed and imported before running these commands.

```powershell
Import-Module ActiveDirectory
```

---

## 📂 AD Users Management

### 🔍 List All Users

```powershell
Get-ADUser -Filter *
```

### ℹ️ Get Specific User Information

```powershell
Get-ADUser user1
Get-ADUser user1 -Properties *
```

### 🗂 Get Users from a Specific OU

```powershell
Get-ADUser -Filter * -SearchBase "OU=External,OU=Accounts,OU=CompanyName,DC=Domain,DC=local"
```

### 🔎 Search for Users by Name Pattern

```powershell
Get-ADUser -Filter * | Where-Object Name -like '*user1*'
```

### 📅 Show User Account Expiration Date

```powershell
Get-ADUser user1 -Properties AccountExpirationDate | Select-Object AccountExpirationDate
```

### 🏢 Get Users from a Specific Department

```powershell
Get-ADUser -Filter { department -eq 'Exploration' }
```

### 🔓 Unlock a User Account

```powershell
Unlock-ADUser user1
```

### 🧾 Get Last Logon Time

```powershell
Get-ADUser -Identity "user1" -Properties LastLogon | Select-Object Name, @{Name='LastLogon';Expression={[DateTime]::FromFileTime($_.LastLogon)}}
```

### ⏳ Get Account Age in Days

```powershell
Get-ADUser -Filter * -Properties WhenCreated | Select-Object Name, @{Name='Account Age (days)'; Expression={(New-TimeSpan -Start $_.WhenCreated).Days}}
```

### 🔁 Copy Group Membership from One User to Another

```powershell
$Oldusername = "mmichaud"
$Newusername = "m.michaud"

Get-ADUser -Identity $Oldusername -Properties MemberOf |
    Select-Object -ExpandProperty MemberOf |
    Add-ADGroupMember -Members $Newusername
```

### 📅 Get Last Logon for a User

```powershell
Get-ADUser pcontreras -Properties lastLogon | Select-Object SamAccountName, @{Name="LastLogon"; Expression={[datetime]::FromFileTime($_.LastLogon)}}
```

### ⛔ Get All Users Inactive for Over 90 Days

```powershell
$Date = (Get-Date).AddDays(-90)
Get-ADUser -Filter { (Enabled -eq $true) -and (LastLogonDate -lt $Date) } -Properties LastLogonDate |
    Select-Object SamAccountName, Name, LastLogonDate |
    Sort-Object LastLogonDate
```

---

## 👥 AD Groups Management

### 📋 List All Groups

```powershell
Get-ADGroup -Filter *
```

### ✅ Check if a Group Exists

```powershell
Get-ADGroup -Identity 'HR'
```

### 🔒 List Only Security Groups

```powershell
Get-ADGroup -Filter 'GroupCategory -eq "Security"'
```

---

## 👤 Group Membership Management

### 👨‍👩‍👧 Get Members of a Group

```powershell
Get-ADGroupMember -Identity 'HR'
```

### 🔁 Get Members Recursively (Including Nested Groups)

```powershell
Get-ADGroupMember -Identity 'HR' -Recursive
```

### 🧾 List Members of Multiple Groups

```powershell
$groupNames = 'HR', 'Accounting', 'IT'
foreach ($group in $groupNames) {
    Get-ADGroupMember -Identity $group
}
```

---

## ➕ Create a New AD User

### 👤 Create a User Account

```powershell
New-ADUser `
    -Name "TestUser" `
    -Path "OU=TestOU,DC=TestDomain,DC=Local" `
    -SamAccountName "TestUser" `
    -DisplayName "Test User" `
    -AccountPassword (ConvertTo-SecureString "MyPassword123" -AsPlainText -Force) `
    -ChangePasswordAtLogon $false `
    -PasswordNeverExpires $true `
    -Enabled $true
```

### 🔗 Add the New User to a Group

```powershell
Add-ADGroupMember "Domain Admins" "TestUser"
```

---

## 📌 Notes

* Use elevated PowerShell to execute these commands.
* Replace placeholder values like `user1`, `Domain`, or `TestUser` with real values.
* Always test scripts in a development environment before applying to production.

---

## 📄 License

This project is released under the [MIT License](LICENSE).

