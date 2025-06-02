
#============================ 8- Function Close-RDS-Sessions =================================
# Notify All RDS connected users in the Broker
# This Function take as parameter the list of connected users from privious function : Get-Connected-Users

function Close-RDSSessions
{
	[CmdletBinding()]
	param
    (
        [Parameter(Mandatory = $true)]
		[string] $Broker ,
        
        [Parameter(Mandatory = $true)]
		$RD_Users_Sessions
	)

    # Close all users Session
    Write-Host "`n`nTrying to Disconnect all users session in the Broker...................... Progress`n" -ForegroundColor Yellow
    Write-LogFile "`n`n=========================  Trying to Disconnect all users session in the Broker =================================`n"
    foreach($uid in $RD_Users_Sessions)
    {
        try 
        {
            Disconnect-RDUser -UnifiedSessionID $uid.SessionId -HostServer $uid.HostServer -Force -ErrorVariable Disconnection
            Invoke-RDUserLogoff -UnifiedSessionID $uid.SessionId -HostServer $uid.HostServer -Force -ErrorVariable Logoff
            Write-Host "User : "($uid).UserName "   : disconnected from " $uid.HostServer " ........................  OK " -ForegroundColor Green
            $Message = "User : " + ($uid).UserName + "   : disconnected from " + $uid.HostServer + " ........................  OK "
            Write-LogFile $Message
        }
        catch 
        {
            if (&Disconnection) 
            {
                Write-Host "Error while trying to disconnect User : "($uid).UserName "  from " $uid.HostServer " ........................  Error " -ForegroundColor Red
                $Message = "Error while trying to disconnect User : " + ($uid).UserName + "  from " + $uid.HostServer + " ........................  Error "
                Write-LogFile $Message
            }          
            if (&Logoff) 
            {
                Write-Host "Error while trying to Logoff User : "($uid).UserName "  from " $uid.HostServer " ........................  Error " -ForegroundColor Red
                $Message = "Error while trying to Logoff User : " + ($uid).UserName + "  from " + $uid.HostServer + " ........................  Error "
                Write-LogFile $Message
            }          
        }
    }
}

