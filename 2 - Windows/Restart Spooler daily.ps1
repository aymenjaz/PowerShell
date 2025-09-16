# Restart Spooler daily at 13:00
# Task Name
$TaskName = "RestartPrintSpooler"
# Scheduled time for this task
$TaskTime = "13:00"

# Task settings : Action + Trigger + Principal executer
$Action   = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command Restart-Service -Name Spooler -Force"
$Trigger  = New-ScheduledTaskTrigger -Daily -At $TaskTime
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create schedule
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Description "Restarts Print Spooler daily at 13:00"
