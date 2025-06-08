Set-ExecutionPolicy RemoteSigned -Force

# Import Exchange Online module
Import-Module ExchangeOnlineManagement

# connect to Exchange Online
Connect-ExchangeOnline 

# Find the permissions required to run any Exchange cmdlet
$Perms = Get-ManagementRole -Cmdlet "Cmdlet"  # [-CmdletParameters <Parameter1>,<Parameter2>,...]

# If you specify multiple parameters, only roles that include all of the specified parameters on the cmdlet are returned.
$Perms | foreach {Get-ManagementRoleAssignment -Role $_.Name -Delegating $false | Format-Table -Auto Role,RoleAssigneeType,RoleAssigneeName}

Disconnect-ExchangeOnline -Confirm:$false
