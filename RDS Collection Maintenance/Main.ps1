Set-ExecutionPolicy RemoteSigned -Force

# Import Script Write-LogFile
. .\Write-LogFile.ps1

# Import Script Set-StoredVariable
. .\Set-StoredVariable.ps1

# Import Script Get-StoredVariable
. .\Get-StoredVariable.ps1

# Import Script Get-RDSServerList
. .\Get-RDSServerList.ps1

# Import Script Lock-RDSConnection
. .\Lock-RDSConnection.ps1

# Import Script Get-ConnectedUsers
. .\Get-ConnectedUsers.ps1

# Import Script Send-NotificationRDSUsers
. .\Send-NotificationRDSUsers.ps1

# Import Script Close-RDSSessions
. .\Close-RDSSessions.ps1

# Import Script Reset-RDSServers
. .\Reset-RDSServers.ps1

$ErrorActionPreference = 'SilentlyContinue'

Clear-Host 

# Get Broker Server Name
Global $Broker = $env:COMPUTERNAME

Write-Host "`n`n`n`n`n`n`n`n"
# Function to Get list of RDS Servers from Broker
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Get list of RDS Servers from Broker..." -PercentComplete 10
$RDS_Servers = @{}
$RDS_Servers = Get-RDSServerList $Broker


# Lock new connection for RDS Servers 
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Lock new connection for RDS Servers..." -PercentComplete 20
Lock-RDSConnection  $Broker  $RDS_Servers


# Get Connected Users
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Get Connected Users..." -PercentComplete 30
$Connected_Users = @{}
$Connected_Users = Get-ConnectedUsers $Broker


# Send Notification to connected users
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Send Notification to connected users..." -PercentComplete 40
Send-NotificationRDSUsers $Connected_Users

# Sleep for 5 minutes before resending the same message to users 
Start-Sleep -Seconds 30

# Send Notification to connected users
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Send Notification to connected users..." -PercentComplete 50
Send-NotificationRDSUsers $Connected_Users

# Close all RDS Sessions
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Close all RDS Sessions..." -PercentComplete 60
$RD_Users_Sessions  = @{}
$RD_Users_Sessions = Get-ConnectedUsers $Broker
$RD_Users_Sessions
if ($Null -ne $RD_Users_Sessions) 
{
    Close-RDSSessions $Broker $RD_Users_Sessions 
}


# Reset servers : Disconnect Virtual disks , delete user profiles and reboot
#write-progress -activity "=>  RDS Reset : Script Processing , please wait..." -status "Disconnect Virtual disks , delete user profiles and reboot..." -PercentComplete 70
$RDS_Servers
Reset-RDSServers $RDS_Servers

msg * "Broker will restart in 30 second"
# waiting for 30 second before rebooting server
Start-Sleep 30

# Save State of servers
Set-StoredVariable 1

# reboot Broker
#write-progress -activity "=>  reboot Broker : Script Processing , please wait..." -status "reboot..." -PercentComplete 95
Restart-Computer $Broker -Force

