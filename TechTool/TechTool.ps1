Clear-Host
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Function Clear-ResourceEnvironment
{
    # Perform garbage collection on session resources 
    [System.GC]::Collect()         
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    # Remove any custom varialbes created
    Get-Variable -Name MyShell -ErrorAction SilentlyContinue | Remove-Variable
    Clear-Host
}

$menu = @"
*******************************************************************************
SysAdminTool v1.1 Created By Aymen EL JAZIRI .... Feb 2024
*******************************************************************************

**************************** System Tools ******************************

1) List of latest server restarts/shutsdowns (30-day duration)                             
2) List of KB updates installed on the server (sorted by installation date)           
3) List of uninstalled updates ready for installation             
4) Windows Defender Status                                              
5) History of users connected to server
6) List of files whose size has recently increased excessively (15 days ago)
7) List of 50 system errors in LogEvent
8) List of stopped services
9) Clean up All system Temp files 
10) Get ip location and informations

**************************** Softwares Tools **********************************

20) Auto download and Install Google Chrome Browser
21) Auto download and Install Brave Browser
22) Auto download and Install IP Scanner Tool
23) Auto download and Install TreeSize

*******************************************************************************
x) to end the program
*******************************************************************************

"@

$host.ui.RawUI.WindowTitle = "SysAdminTool v1.0 By Aymen EL JAZIRI"

#==========================================================================================================================================
Function Get-RebootHistory 
{
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $false,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string[]]  $ComputerName = $env:COMPUTERNAME,
    
        [int]       $DaysFromToday = 7,
    
        [int]       $MaxEvents = 9999
    )
    BEGIN {}
    PROCESS 
    {
        foreach ($Computer in $ComputerName) 
        {
            try {
                $Computer = $Computer.ToUpper()
                $EventList = Get-WinEvent -ComputerName $Computer -FilterHashtable @{
                    Logname = 'system'
                    Id = '1074', '6008'
                    StartTime = (Get-Date).AddDays(-$DaysFromToday)
                } -MaxEvents $MaxEvents -ErrorAction Stop
    
                foreach ($Event in $EventList) 
                {
                    if ($Event.Id -eq 1074) 
                    {
                        [PSCustomObject]@{
                            TimeStamp    = $Event.TimeCreated
                            ComputerName = $Computer
                            UserName     = $Event.Properties.value[6]
                            ShutdownType = $Event.Properties.value[4]
                        }
                    }
    
                    if ($Event.Id -eq 6008) 
                    {
                        [PSCustomObject]@{
                            TimeStamp    = $Event.TimeCreated
                            ComputerName = $Computer
                            UserName     = $null
                            ShutdownType = 'unexpected shutdown'
                        }
                    }
                }
            } 
            catch 
            {
                Write-Error $_.Exception.Message
            }
        }
    }
    
    END {}
}
# Get-RebootHistory 
#==========================================================================================================================================
function Get-AvailableUpdates 
{
    param ()
    
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateupdateSearcher()
    $Updates = @($UpdateSearcher.Search("IsHidden=0 and IsInstalled=0").Updates) | Select-Object Title, IsMandatory, IsBeta , IsDownloaded , IsInstalled | Format-Table
    return $Updates
}
# Get-AvailableUpdates
#==========================================================================================================================================
function Get-WDFStatus 
{
    param ()
    $Var = Get-MpComputerStatus  | Select-Object AMRunningMode ,RealTimeProtectionEnabled, AMServiceEnabled , AntispywareEnabled , AntivirusEnabled, AntispywareSignatureLastUpdated  , AntivirusSignatureLastUpdated , DefenderSignaturesOutOfDate 
    return $Var
}
# Get-WDFStatus 
#==========================================================================================================================================
function Get-ConnectedUsersHistory 
{
    param ()
    $UserProperty = @{n="user";e={(New-Object System.Security.Principal.SecurityIdentifier $_.ReplacementStrings[1]).Translate([System.Security.Principal.NTAccount])}}
    $TypeProperty = @{n="Action";e={if($_.EventID -eq 7001) {"Logon"} else {"Logoff"}}}
    $TimeProeprty = @{n="Time";e={$_.TimeGenerated}}
    $ListUsers = Get-EventLog System -Source Microsoft-Windows-Winlogon | Select-Object $UserProperty,$TypeProperty,$TimeProeprty | Sort-Object Time -Descending |  Format-Table -autosize
    return $ListUsers
}
# Get-ConnectedUsersHistory
#==========================================================================================================================================
function ListOfModifiedFiles 
{
    param ()
    
    Write-Host("Noter bien que le temps d'execution de cette commande depend de la taille du dossier a scanner") -ForegroundColor Red
    Write-Host("Entrer le chemain du dossier à scanner") -ForegroundColor Yellow
    $Directoryscan = Read-Host("Scan Path ")
    Write-Host("Entrer un nombre qui designe la taille minimale des fichiers a scanner en MB") -ForegroundColor Yellow
    $MinimumSize = Read-Host("un nombre ")
    
    if((Test-Path $Directoryscan) )
    {
        if ( $MinimumSize -gt 0 ) 
        {

            #we can include or exclude some file extension (-include *.log  -exclude *.mp4)
            Get-ChildItem -Path $Directoryscan -Recurse -Force -EA 0 | 
            Select-Object Name , @{label = 'SizeMB'; expression = {$_.Length/ 1mB -as [int]}}, LastWriteTime , FullName  | Sort-Object -Descending 'SizeMB' |
            Where-Object { ($_.LastWriteTime -gt (Get-Date).AddDays(-15) ) -and ($_.SizeMB -gt $MinimumSize)} #-ErrorAction SilentlyContinue
        }
        else 
        {
            Write-Host("la taille minimale des fichiers à rechercher doit etre minimum 1 : $MinimumSize") -ForegroundColor Red
        }
    }
    else 
    {
        Write-Host("dossier non existant : $Directoryscan") -ForegroundColor Red
    }
}
# ListOfModifiedFiles

#==========================================================================================================================================
function SetupGoogleChrome 
{
    param ()
    # Create a temporary directory to store Google Chrome.
    mkdir -Path $env:temp\chromeinstall -erroraction SilentlyContinue | Out-Null
    $Download = join-path $env:temp\chromeinstall chrome_installer.exe
    # Download the Google Chrome installer.
    Invoke-WebRequest 'http://dl.google.com/chrome/install/375.126/chrome_installer.exe'  -OutFile $Download
    # Install Google Chrome using Powershell.
    Invoke-Expression "$Download /install"
}
# SetupGoogleChrome
#==========================================================================================================================================
function SetupBrave 
{
    param ()
    # Create a temporary directory to store Brave64
    mkdir -Path $env:temp\Brave -erroraction SilentlyContinue | Out-Null
    $Download = join-path $env:temp\Brave Brave64.exe
    # Download the Brave installer.
    Invoke-WebRequest 'https://laptop-updates.brave.com/latest/winx64/Brave64.exe' -OutFile $Download
    # Install Google Brave using Powershell.
    Invoke-Expression "$Download /install"
}
# SetupBrave
#==========================================================================================================================================
function SetupIpScanner 
{
    param ()
    # Create a temporary directory to store ipscanner
    $Dir = "C:\temp\" 
    if((Test-Path $Dir) -eq $false)
    {
        New-Item -ItemType Directory -Path $Dir -erroraction SilentlyContinue | Out-Null
    }
    $Download = $Dir + "ipscanner.exe"
    # Download the ipscanner
    Invoke-WebRequest 'https://download.advanced-ip-scanner.com/download/files/Advanced_IP_Scanner_2.5.4594.1.exe'  -OutFile $Download
    # execute ipscanner using Powershell.
    Invoke-Expression "$Download /install"
}
# SetupIpScanner 
#==========================================================================================================================================
function SetupTreeSize
{
    param ()

    # set protocol to tls version 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Create a temporary directory to store TreeSize
    mkdir -Path $env:temp\TreeSize -erroraction SilentlyContinue | Out-Null
    $Download = join-path $env:temp\TreeSize TreeSize.exe
    $TempFile = join-path $env:temp\TreeSize _tmp.txt

    # Download the TreeSize installer.
    $TreeSize = "https://drive.google.com/uc?export=download&id=1swli5X0KfZkyVW9RW-b4ZiGy-emovAUH" 

    Invoke-WebRequest -Uri $TreeSize -OutFile  $TempFile -SessionVariable googleDriveSession

    # Get confirmation code from _tmp.txt
    $searchString =  Get-Content -Path $TempFile

    $Regex = [Regex]::new("(uuid=)(.*)(`" method)")           
    $Match = $Regex.Match($searchString)           
    if($Match.Success)           
    {           
        $uuid = $Match.Value 
        $uuid = $uuid -replace "uuid=" , ""
        $uuid = $uuid -replace "`" method" , "" 
        #$uuid        
    }

    # Download the real file
    Invoke-WebRequest -Uri "https://drive.google.com/uc?export=download&id=1swli5X0KfZkyVW9RW-b4ZiGy-emovAUH&confirm=t&uuid=$uuid" -OutFile $Download #-WebSession $googleDriveSession

    # Install TreeSize using Powershell.
    Invoke-Expression "$Download /install"
}
# SetupTreeSize
#==========================================================================================================================================
function CleanUpDisk 
{
    param ()

    $TempFileLocation = "$env:windir\Temp","$env:TEMP" , "$env:windir\SoftwareDistribution\Download"
    $TempFile = Get-ChildItem $TempFileLocation -Recurse
    $TempFileCount = ($TempFile).count

    if($TempFileCount -eq "0") 
    { 
        Write-Host "There are no files in the folder $TempFileLocation" -ForegroundColor Green
    }
    Else 
    {
        $TempFile | Remove-Item -Confirm:$false -Recurse -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Write-Host "Cleared $TempFileCount files in the folder $TempFileLocation" -ForegroundColor Green
    }
}

# Main Menu
do
{
    cmd /c color 71
    Clear-ResourceEnvironment
    [Console]::WriteLine($menu)
    $Selection = Read-Host("Entrer votre choix ")
    Clear-ResourceEnvironment
    Switch($Selection)
    {
        1 {
            Write-Host "`n`n Liste des Derniers Redemarrage/Arret du serveur (Duree de 30 Jours) :" -BackgroundColor Green
            Get-RebootHistory -DaysFromToday 30 -MaxEvents 20  | Format-Table -AutoSize
            pause
        }

        2 {
            Write-Host "`n`n Liste des updates KB installee sur le serveur (Triees par date) :" -BackgroundColor Green
            Get-HotFix | Sort-Object  InstalledOn -Descending | Format-Table -AutoSize
            pause
        }

        3 {
            Write-Host "`n`n Liste des updates non Installee et pret pour installation :" -BackgroundColor Green
            Get-AvailableUpdates 
            pause
        }

        4 {
            Write-Host "`n`n Windows Defender Status : " -BackgroundColor Green
            Get-WDFStatus 
            pause
        }

        5 {
            Write-Host "`n`n Historique des users connectee sur le serveur :" -BackgroundColor Green
            Get-ConnectedUsersHistory
            pause
        }

        6 {
            Write-Host "`n`n Liste des fichiers dont la taille a augmente dernierement d une maniere excessive `(15 jours en arriere`) :" -BackgroundColor Green
            ListOfModifiedFiles
            pause
        }

        7 {
            Write-Host "`n`n List des 50 erreur Systeme dans le LogEvent : "-BackgroundColor Green
            Get-EventLog -LogName System | Where-Object EntryType -EQ "Error" | Sort-Object -Descending Time | Select-Object -First 50
            pause
        }

        8 {
            Write-Host "`n`n Liste des services arretee" -BackgroundColor Green
            Get-Service | Where-Object Status -EQ 'Stopped' | Sort-Object DisplayName | Format-Table -AutoSize
            pause
        }

        9 {
            Write-Host "`n`n Clean up Disk system Temp Files" -BackgroundColor Green
            CleanUpDisk
            pause
        }

        10 {
            Write-Host `n`n 'Get ip location and informations :' -BackgroundColor Green
            # Get information about public ip adress : location , HostName , city, Region , postal , timezone...
            $ExternalIP = Read-Host("Please Enter External IP adress that you want to check location ") 
            Invoke-RestMethod -Uri https://ipinfo.io/$ExternalIP | Select-Object Ip, Hostname, City, Region, Country, @{label = "GPS Location";E={$_.loc}} , @{label ="Company";E={$_.org}}, @{label ="Postal Code";E={$_.postal}} , timezone
            pause
        }

        11 {
            Clear-ResourceEnvironment
            Write-Host `n`n '.............................................' -BackgroundColor Green
            
            pause
        }

        20 {
            Write-Host `n`n 'Auto download and Install Google Chrome Navigator :' -BackgroundColor Green
            SetupGoogleChrome
            pause
        }

        21 {
            Write-Host `n`n 'Auto download and Install Brave Navigator :' -BackgroundColor Green
            SetupBrave
            pause
        }

        22 {
            Write-Host `n`n 'Auto download and Install IP Scanner Tool :' -BackgroundColor Green
            SetupIpScanner
            pause
        }

        23 {
            Write-Host `n`n 'Auto download and Install TreeSize : ' -BackgroundColor Green
            SetupTreeSize
            pause
        }

        'x'{
            Write-Host `n`n '           Good Bye ;-) ' -BackgroundColor Green
            Start-Sleep 3
        }

        default
        {
            Write-Host `n`n 'Please Enter Numbers in the Menu !!!' -BackgroundColor Red
            pause -foregroundColor DarkGray -BackgroundColor Green 
        }
    }
    
}Until($Selection -eq 'x')

switch($PSVersionTable.PSEdition)
{
    'Core' {cmd /c color 07}
    'Desktop' {cmd /c color 07}
    Default {cmd /c color 07}
} 
