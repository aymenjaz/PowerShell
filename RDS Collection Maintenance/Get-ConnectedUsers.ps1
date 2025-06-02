
#=========================== 6- Function Get-Connected-Users =================================
# Get list of connected users in the Broker
# This Function take as parameter the Broker

function Get-ConnectedUsers
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $true)]
		[string] $Broker
	)

    # Get list of users session in the Broker
    $RD_Users_Sessions = ""
    Write-Host "`n`n=========================Trying to Get list of users session in the Broker =========================`n" -ForegroundColor Yellow
    Write-LogFile "`n`n=========================  Trying to Get list of users session in the Broker =================================`n"
    try 
    {
        $RD_Users_Sessions = Get-RDUserSession -ConnectionBroker $Broker
        Write-Host "list of users session in the Broker ................. OK" -ForegroundColor Green
        Write-LogFile "list of users session in the Broker ................. OK"
        return $RD_Users_Sessions
    }
    catch 
    {
        Write-Host "Get list of users session in the Broker ................. Error" -ForegroundColor Red
        Write-LogFile "Get list of users session in the Broker ................. Error"
        return 0
    }

}

