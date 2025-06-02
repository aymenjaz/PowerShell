
#======================== 4- Function Get-RDS-Server-List ===================================
# Function to Get list of RDS Servers from Broker
function Get-RDSServerList
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $true)]
		[string] $Broker
	)
	
    Write-Host "`n`n========================= Trying to Get list of RDS Servers from Broker =========================`n" -ForegroundColor Yellow
    Write-LogFile "`n`n========================= Trying to Get list of RDS Servers from Broker =================================`n"

    #Get list of servers in RDS Broker
    try 
    {
        $ServerList = Get-RDServer -ConnectionBroker $Broker -Role RDS-RD-SERVER | Select-Object Server
        Write-Host "Get List of RDS Servers from the Broker ................. OK" 
        Write-Host $ServerList -BackgroundColor Green 
        Write-LogFile "Get List of RDS Servers from the Broker ................. OK"
        return $ServerList
    }
    catch 
    {
        Write-Host "Cant Continue , Problem while trying to get list of RDS Servers from the Broker ................. Error" -ForegroundColor Red
        Write-LogFile "Cant Continue , Problem while trying to get list of RDS Servers from the Broker ................. Error"
        Write-Host "No RDS Servers , Cant Continue Program Will Exit" -ForegroundColor White -BackgroundColor Red
        Exit
    }
}

