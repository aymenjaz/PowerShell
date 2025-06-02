# 🔧 Automated RDS Collection Maintenance with PowerShell

This PowerShell project automates the maintenance of a Remote Desktop Services (RDS) Collection, including both the **RD Connection Broker** and all associated **RDS session hosts**. The script is designed to be executed during scheduled maintenance windows and includes full logging to help with troubleshooting and auditing.

> ✅ Modular, automated, and user-aware — this script reduces manual work while ensuring a safe and clean reboot cycle.

---

## 📋 Features

The `Main.ps1` script performs the following actions in sequence:

1. **Retrieve RD Connection Broker name**
   - Detects and logs the RD Connection Broker automatically.
2. **Get list of RDS Servers**
   - Retrieves all RDS session hosts linked to the Broker.
3. **Lock new connections**
   - Temporarily disables new user logins to prevent interference.
4. **List connected users**
   - Enumerates and logs currently connected RDP sessions.
5. **Send disconnect notifications**
   - Sends user-friendly pop-up messages to notify users.
6. **Wait 15 minutes**
   - Gives users time to log off gracefully.
7. **Repeat notification + wait**
   - Sends a second reminder and waits again.
8. **Forcefully close RDS sessions**
   - Cleanly logs off any remaining sessions.
9. **Per-server tasks**
   - For each RDS server:
     - Disconnect virtual disks
     - Delete user profiles
     - Reboot the machine
10. **Reboot the RD Connection Broker**
11. **Unlock new connections**
   - Re-enables user logins once maintenance is completed.

---

## 🧱 Script Structure

This solution is built using modular `.ps1` files for clarity and reusability:

```bash
├── Main.ps1                         # Orchestrates the full process
├── Get-StoredVariable.ps1
├── Set-StoredVariable.ps1
├── Get-RDSServerList.ps1
├── Lock-RDSConnection.ps1
├── UnLock-RDSConnection.ps1
├── Get-ConnectedUsers.ps1
├── Send-NotificationRDSUsers.ps1
├── Close-RDSSessions.ps1
├── Reset-RDSServers.ps1
└── Write-Log.ps1
```

---

## 🪵 Logging
The script uses a Write-Log function to capture all output, errors, and status updates into a log file. This makes troubleshooting simple and ensures full traceability.

---

## 💡 Why Use This Script?
✅ Consistency: Automates a multi-step RDS maintenance workflow
✅ User communication: Sends real-time disconnect warnings
✅ Hygiene: Clears profiles and virtual disks regularly
✅ Safety: Prevents new sessions before and during reboots
✅ Scalable: Works across any number of RDS servers

---

## 📌 Requirements
- Windows Server with RDS Role configured
- PowerShell 5.1 or later
- Admin privileges on all RDS hosts
- Remote PowerShell enabled between hosts : This PowerShell Script must be executed on each RDS server

> Remember : Replace Broker Server Name with your Broker Name.

```PowerShell
# the WinRM and PSRemoting commands use ports 5985 for HTTP and 5986 for HTTPS
# so make sure these ports are not blocked by the network firewall

# Set Broker Server Name
$Broker = "BROKER.domain.LOCAL"

# 1- Enable WinRm
winrm quickconfig

# 2- Enable Powershell Remote
Enable-PSRemoting -Force

# Set the Broker in List Of Trusted Hosts
$curList = (Get-Item WSMan:\localhost\Client\TrustedHosts).value
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$curList , $($Broker)"


# Get List Of Trusted Hosts for one Server
Get-Item WSMan:\localhost\Client\TrustedHosts
```

---

## 🙌 Contributions
Feel free to fork, improve, or open issues. Contributions are welcome!

---

## 📄 License
This script is provided as-is under the MIT License.
