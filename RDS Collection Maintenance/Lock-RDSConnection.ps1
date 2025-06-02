
#=========================== 5- Function Lock-Connectionto-RDS-Servers =================================
# Lock new Connections for all servers in the Broker
# This Function take as parameter a list of servers varaible which returned by the previous function : Get-RDS-Server-List
function Lock-RDSConnection
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $true)]
		[string] $Broker ,
        
        [Parameter(Mandatory = $true)]
		$ServerList 
	)

    Write-Host "`n`n========================= Trying to Lock new Connections for all servers in the Broker =========================`n" -ForegroundColor Yellow
    Write-LogFile "`n`n========================= Trying to Lock new Connections for all servers in the Broker =================================`n"

	if (($Null -ne $Broker) -or ($Null -ne $ServerList))
    {
        foreach($SRV in $ServerList)
        {
            Write-Host "try to Lock Connection for Server : " $SRV.Server "................. "
            try 
            {
                Set-RDSessionHost -SessionHost $SRV.Server -NewConnectionAllowed No -ConnectionBroker $Broker -ErrorAction "SilentlyContinue"
                Write-Host "Connection Locked for Server : " $SRV.Server " ................. OK" -ForegroundColor Green
                $Message =  "Connection Locked for Server : " + $SRV.Server + " ................. OK"
                Write-LogFile $Message
            }
            catch 
            {
                Write-Host "Problem while trying to lock Connection for Server : " $SRV.Server "................. Error" -ForegroundColor Red
                $Message = "Problem while trying to lock Connection for Server : " + $SRV.Server +" ................. Error"
                Write-LogFile $Message
            }
        }
    }
    else 
    {
        Write-Host "Parametre Error : Broker or Server list is Null "
        Write-Host "Broker : $Broker"
        Write-Host "Server List : $ServerList"
    }
    
}

