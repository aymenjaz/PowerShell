

# Script for cleaning up RDS VHDX Files
# Open each VHDX file then cleanup certain folders Like Download and RecycleBin to free up space

# Dir that contain VHDX Files
$VHD_Directory = "C:\Temp\"

# Specifie here Directorys to be cleaned
$recycle = '$RECYCLE.BIN' , 'Downloads' 

# Define Error Action
$ErrorActionPreference = 'SilentlyContinue'

# Get list of vhd , vhdx files from original directory
$VHD_Files = Get-ChildItem $VHD_Directory -Recurse -Include *.vhd , *.vhdx -Force | Select-Object Name
# $VHD_Files


foreach ($VhdFile  in $VHD_Files) 
{
    # file path
    $FilePath = $VHD_Directory + $VhdFile.Name
    # $FilePath

    # run the Mount-VHD cmdlet to mount your vhd/vhdx file.
    try 
    {
        if( (Get-DiskImage -ImagePath $FilePath | Select-Object Attached).Attached -eq $false )
        {
            if(Mount-DiskImage -ImagePath $FilePath -ErrorVariable MountError)
            {
                Start-Sleep 2
                
                # get Letter for mounted disk
                $Mounted_Drive = Get-DiskImage -ImagePath $FilePath | Get-Disk | Get-Partition | Get-Volume | Select-Object DriveLetter
                # $Mounted_Drive

                foreach($dir in $recycle)
                {
                    if(Test-Path "$($Mounted_Drive.DriveLetter):\$($dir)\")
                    {
                        # Delete all objects in $recycle
                        Remove-Item  -Path "$($Mounted_Drive.DriveLetter):\$($dir)\*" -Recurse -Force -ErrorVariable DeleteError -ErrorAction SilentlyContinue
                    }
                    else
                    {
                        Write-Host "Error : Directory $($Mounted_Drive.DriveLetter):\$($dir)\ not Found " -ForegroundColor Yellow
                    }

                }
                
                # Close opned window for mounted volume
                $shell = New-Object -ComObject Shell.Application
                $window = $shell.Windows() | Where-Object { $_.LocationURL -eq ("file:///" + $Mounted_Drive) }
                $window | ForEach-Object { $_.Quit() }

                # unmount virtual hard disk
                Dismount-DiskImage -ImagePath $FilePath -ErrorVariable DismountError

                Write-Host "VHDX File -- $($FilePath) -- Cleaned Successfully" -ForegroundColor Green
                
            }
        }
        else
        {
            Write-Host "The current file -- $($FilePath) -- is already mounted" -ForegroundColor Yellow
        }
    }
    catch 
    {
        if(&MountError)
        {
            Write-Host "Error while Trying to Mount file : $($FilePath)" -ForegroundColor Red
        }
        if(&DeleteError)
        {
            Write-Host "Error while Trying to Delete files from : $($Mounted_Drive.DriveLetter):\$($dir)\ " -ForegroundColor Red
        }
        if(&DismountError)
        {
            Write-Host "Error while Trying to Dismount file : $($FilePath)" -ForegroundColor Red
        }
    }

}

