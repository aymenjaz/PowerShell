
#=========================== 5- Function Lock-Connectionto-RDS-Servers =================================
# Lock new Connections for all servers in the Broker
# This Function take as parameter a list of servers varaible which returned by the previous function : Get-RDS-Server-List


$ErrorActionPreference = 'SilentlyContinue'

Clear-Host 

# Define Broker Name
$Broker = "BROKER.RDSLAB.LOCAL"

# Import Script Write-LogFile
. .\Write-LogFile.ps1

# Import Script Get-StoredVariable
. .\Get-StoredVariable.ps1

# Import Script Get-RDSServerList
. .\Get-RDSServerList.ps1

# Import Script Set-StoredVariable
. .\Set-StoredVariable.ps1

function UnLock-RDSConnection
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $true)]
		[string] $Broker ,
        
        [Parameter(Mandatory = $true)]
		$ServerList 
	)

    Write-Host "`n`n========================= Trying to UnLock new Connections for all servers in the Broker =========================`n" -ForegroundColor Yellow
    Write-LogFile "`n`n========================= Trying to UnLock new Connections for all servers in the Broker =================================`n"

	if (($Null -ne $Broker) -or ($Null -ne $ServerList))
    {
        foreach($SRV in $ServerList)
        {
            Write-Host "try to UnLock Connection for Server : " $SRV.Server "................. "
            try 
            {
                Set-RDSessionHost -SessionHost $SRV.Server -NewConnectionAllowed Yes -ConnectionBroker $Broker -ErrorAction "SilentlyContinue"
                Write-Host "Connection UnLocked for Server : " $SRV.Server " ................. OK" -ForegroundColor Green
                $Message =  "Connection UnLocked for Server : " + $SRV.Server + " ................. OK"
                Write-LogFile $Message
            }
            catch 
            {
                Write-Host "Problem while trying to UnLock Connection for Server : " $SRV.Server "................. Error" -ForegroundColor Red
                $Message = "Problem while trying to UnLock Connection for Server : " + $SRV.Server +" ................. Error"
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

# Set-StoredVariable 1

if((Get-StoredVariable) -eq 1)
{
    Write-Host "`n`n"
    $Msg = "Trying to reconnect RDS Servers "
    for($i=0 ; $i -lt 10 ; $i++)
    {
        Clear-Host
        $Msg = $Msg + "."
        write-host $Msg -ForegroundColor Yellow
        Start-Sleep 1
    }


    # Function to Get list of RDS Servers from Broker
    # write-progress -activity "=> MS Solutions RDS Reset : Script Processing , please wait..." -status "Get list of RDS Servers from Broker..." -PercentComplete 10
    $RDS_Servers = @{}
    $RDS_Servers = Get-RDSServerList $Broker

    Start-Sleep 3

    # Function to unlock RDS Servers
    UnLock-RDSConnection  $Broker  $RDS_Servers

    Set-StoredVariable 0

}


