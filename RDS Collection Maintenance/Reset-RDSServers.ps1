
#=============================== 9- Function CleanRDS-Servers =================================
# Opening Session with Every Server , disconnect Virtual Disks , Delete distant user profile in RDS Server
# 1- Connect to to RDS Server and unmount all Virtual disks
function Reset-RDSServers
{
	[CmdletBinding()]
	param
    (
        [Parameter(Mandatory = $true)]
		$RDS_Servers
    )
    
    Write-Host "`n`n========================= Trying to Disconnect all users VHD and Delete Users Profile in every server =========================`n" -ForegroundColor Yellow
    Write-LogFile "`n`n========================= Trying to Lock new Connections for all servers in the Broker =================================`n"

    foreach($Server in $RDS_Servers)
    {
        Write-Host  "Processing For Server : $($Server.Server) ........................" -ForegroundColor Green 
        try 
        {
            # Make Trusted Session with RDS Server
            Enter-PSSession -ComputerName $Server.Server -ErrorVariable MakingSession
            # --------------------- Second Section : Delete Users Profile in every server ------------------
            # Get list of Virtual disk attached to the system
            $Virtual_Disks = Get-Disk | Where-Object BusType -eq "File Backed Virtual"
            
            # Unmount all disks from the System
            if( $Null -ne $Virtual_Disks)
            {
                Foreach($Disk in $Virtual_Disks)
                {
                    try
                    {
                        # Disconnect  VirtualDisk
                        Dismount-DiskImage -ImagePath $Disk.Location -Confirm:$false -ErrorVariable DismountDisk
                        Write-Host  "Disk $($Disk.Number) ($($Disk.Size/1GB) GB) Dismounted .................. OK" -ForegroundColor Green 
                        Write-LogFile "Disk $($Disk.Number) ($($Disk.Size/1GB) GB) Dismounted .................. OK"
                    }
                    catch
                    {
                        Write-Host "Disk $Disk.Number ($($Disk.Size/1GB) GB) Dismount Error .................. OK" -ForegroundColor Red 
                        Write-LogFile "Disk $Disk.Number ($($Disk.Size/1GB) GB) Dismount Error .................. OK"
                    }
                }
            }
            else
            {
                Write-Host "No Disks to Dismount" -ForegroundColor Cyan
                Write-LogFile "No Disks to Dismount"
            }
            Exit-PSSession
        }
        catch 
        {
            if(&MakingSession)
            {
                Write-Host "Error while making Session with server $($Server.Server)"
                Write-LogFile "Error while making Session with server $($Server.Server)"
            }
            if(&DismountDisk)
            {
                Write-Host "Error while Dismounting Disk $($Disk.Number) ($($Disk.Size/1GB) GB)"
                Write-LogFile "Error while Dismounting Disk $($Disk.Number) ($($Disk.Size/1GB) GB)"
            }
        }
        
        # --------------------- Second Section : Delete Users Profile in every server ------------------

        
        
        # Get list of distant RDS Server Account
        $RDS_Accounts = Get-WmiObject -Class Win32_UserAccount -Filter "LocalAccount=False" | Sort-Object Name | Select-Object Name 
        
        # Get list of subfolders in RDS Server
        $Sub_Folders = Get-ChildItem -force 'C:\Users\'-ErrorAction SilentlyContinue | Where-Object { $_ -is [io.directoryinfo] } 
        foreach($User_Dir in $Sub_Folders)
        {
            Remove-Item -Path "C:\Users\$($User_Dir)" -Confirm:$false
        }

        #Get-LocalUser
        #Get-WmiObject  -Class Win32_ComputerSystem | Select-Object UserName

        Restart-Computer $Server.Server -Force
        Exit-PSSession
        Write-Host "Reboot du serveur : $($Server.Server)" -BackgroundColor Green 
        Write-LogFile "Reboot du serveur : $($Server.Server)"
    }

}

