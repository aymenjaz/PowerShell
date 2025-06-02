# Import Script Write-LogFile
. .\Write-LogFile.ps1

#================================== 7- Function Notify-RDS-Users =================================
# Notify All RDS connected users in the Broker
# This Function take as parameter the list of connected users from privious function : Get-Connected-Users

function Send-NotificationRDSUsers
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $true)]
		$RD_Users_Sessions
	)

    if($null -ne $RD_Users_Sessions)
    {
        Write-Host "`n`nNotify users to quit there session before rds restart using message box`n`n"  -ForegroundColor Yellow
        Write-LogFile "`n`nNotify users to quit there session before rds restart using message box`n`n"

        foreach($uid in $RD_Users_Sessions)
        {
            try
            {
                Send-RDUserMessage -HostServer $uid.HostServer -UnifiedSessionID $uid.UnifiedSessionID -MessageTitle "Alerte Message from Admin" -MessageBody "Please leave this session , Server restart in few minutes !!!"
                Write-Host "Message sent For User : "($uid).UserName "........................  OK " -ForegroundColor Green
                $Message = "Message sent For User : " + ($uid).UserName + "........................  OK "
                Write-LogFile $Message
            }
            catch 
            {
                Write-Host "Notify All RDS connected users in the Broker ................. Error" -ForegroundColor Red
                $Message = "Notification User : " + ($uid).UserName + " Error ........................  Error "
                Write-LogFile $Message
            }
        }
    }
    else 
    {
        Write-Host "no user to notify" -ForegroundColor Cyan
        Write-LogFile "no user to notify"
    }
}

