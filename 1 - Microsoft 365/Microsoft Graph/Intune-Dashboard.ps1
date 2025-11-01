# -------------------------------------------------- Change this variables Only -----------------------------------------
# Connect using app credentials
$TenantId = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$ClientId = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$ClientSecret = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# -------------------------------------------------- Graph Connection Section -----------------------------------------
$Scope = "https://graph.microsoft.com/.default"
$AuthUrl =
"https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$Body = @{
    client_id = $ClientId
    scope = $Scope
    client_secret = $ClientSecret
    grant_type = "client_credentials"
}
$Connection = Invoke-RestMethod -Method POST -Uri $AuthUrl -Body $Body -ContentType "application/x-www-form-urlencoded"
$AccessToken = $Connection.access_token

# Convert token to SecureString
$SecureToken = ConvertTo-SecureString -String $AccessToken -AsPlainText -Force

# Use the token for authentication
Connect-MgGraph -AccessToken $SecureToken

# ----------------------------------------- Install Required Modules -------------------------------------------------
if(!(Get-Module -Name PSWriteHTML -ListAvailable))
{
    Install-Module -Name PSWriteHTML -Force -AllowClobber
    #Update-Module -Name PSWriteHTML -Force
}
Import-Module PSWriteHTML

if(!(Get-Module -Name Microsoft.Graph -ListAvailable))
{
    Install-Module -Name Microsoft.Graph -Force -AllowClobber
}
#Import-Module Microsoft.Graph

# --------------------------------- Create Output Folder : Temp --------------------------------------------
$OutputFolder = "C:\temp"
if(!(Test-Path $OutputFolder))
{
    mkdir -Path $OutputFolder
}

# --------------------------------- Get All managed Devices ------------------------------------------------------

# Get All managed Devices
$ManagedDevices = Get-MgDeviceManagementManagedDevice -All

# --------------------------------- Device Types inventory -------------------------------------------------------------------------

# Windows devices
$WindowsDevices = $ManagedDevices | Where-Object OperatingSystem -EQ "Windows"

# iOS devices
$iOSDevices = $ManagedDevices | Where-Object OperatingSystem -EQ "iOS"

# Android devices
$AndroidDevices = $ManagedDevices | Where-Object OperatingSystem -EQ "Android"

# Linux devices
$LinuxDevices = $ManagedDevices | Where-Object OperatingSystem -EQ "Linux"

# --------------------------------- RealTime Protection -------------------------------------------------------------------------

$ProtectedDevices = @()
$UnprotectedDevices = @()
foreach ($Device in $ManagedDevices)
{
    if($Device.WindowsProtectionState.RealTimeProtectionEnabled -eq $false)
    {
        $UnprotectedDevices = $UnprotectedDevices + $Device
    }
    else 
    { 
        $ProtectedDevices = $ProtectedDevices + $Device 
    }
}

# ------------------------------------- Compliance summary report ---------------------------------------------------------------------

# Compliance summary report

$CompliantDevices = $ManagedDevices | Where-Object ComplianceState -EQ "compliant"

$NoncompliantDevices = $ManagedDevices | Where-Object ComplianceState -EQ "noncompliant"

# ------------------------------------- inactive devices for 30+ days --------------------------------------------------------------------

# Find devices inactive for 30+ days
$ThirtyDaysAgo = (Get-Date).AddDays(-30)
$InactiveDevices =  $ManagedDevices | Where-Object {$_.LastSyncDateTime -lt $ThirtyDaysAgo} 

# ------------------------------------- devices without primary user ---------------------------------------------------------------------

# Find devices without primary user
$UnassignedDevices = $ManagedDevices | Where-Object {$_.UserPrincipalName -eq $null -or $_.UserPrincipalName -eq ''} 

# ------------------------------------- devices with less than 100 GB free space ---------------------------------------------------------------------

# Find devices with less than 100 GB free space
$MinimumFreeSpace = 100
$LowStorageDevices = $ManagedDevices | Where-Object {($_.FreeStorageSpaceInBytes / 1GB) -lt $MinimumFreeSpace} 

# ----------------------------------------------------------------------------------------------------------

# Check device encryption status
$EncryptedDevices = $ManagedDevices | Where-Object IsEncrypted -EQ $true

$UnecryptedDevices = $ManagedDevices | Where-Object IsEncrypted -EQ $false

# ----------------------------------------------------------------------------------------------------------

# Generate Device Inventory Report
$ManagedDevicesTable = $ManagedDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState

# ----------------------------------------------------------------------------------------------------------
# OS Versions
$OSVersions = $WindowsDevices | Select-Object OSVersion | Group-Object OSVersion  | Sort-Object Count -Descending | Select-Object Name , Count -First 10

# ----------------------------------------------------------------------------------------------------------

# PC Manufactor
$Manufactor = $WindowsDevices | Select-Object Manufacturer | Group-Object Manufacturer  | Sort-Object Count -Descending | Select-Object Name , Count -First 10

# ----------------------------------------------------------------------------------------------------------

# Azure Registred Devices
$AzureRegistredDevices = $ManagedDevices | Where-Object AzureAdRegistered -EQ $True

# Azure Unregistred Devices
$AzureUnregistredDevices = $ManagedDevices | Where-Object AzureAdRegistered -EQ $False

# ----------------------------------------------------------------------------------------------------------

# Company Devices
$CompanyDevices = $ManagedDevices | Where-Object ManagedDeviceOwnerType  -EQ 'company'

# Personal Devices
$PersonalDevices = $ManagedDevices | Where-Object ManagedDeviceOwnerType  -EQ 'personal'

# ----------------------------------------------------------------------------------------------------------

New-HTML -TitleText "Intune Dashboard" -Online -FilePath "$OutputFolder\Intune-Dashboard.html" {
    
    # -------------------------------- Devices Section ----------------------------------------------------------------------------------------
    
    New-HTMLSection -HeaderText "Devices Overview" -HeaderTextSize 14 -HeaderBackGroundColor "#708090" -CanCollapse {
        
        # Total Managed intune Devices
        New-HTMLInfoCard -Title "Total Managed intune Devices" -Number $ManagedDevices.Count -Icon "💻" -IconColor "#0078d4" 

        # Devices By Platform
        New-HTMLPanel {
            New-HTMLSection -HeaderText "Devices By Platform" -HeaderTextSize 14 -HeaderTextColor "#000000" -HeaderBackGroundColor "#FFFFFF" {
                New-HTMLColumn {
                    New-HTMLText -Text "Windows" -FontSize 14 -FontWeight bold -Color Blue -Alignment center 
                    New-HTMLText -Text $WindowsDevices.Count -FontSize 48 -FontWeight bold -Color Blue -Alignment center
                }
                New-HTMLColumn {
                    New-HTMLText -Text "iOS" -FontSize 14 -FontWeight bold -Color Green -Alignment center
                    New-HTMLText -Text $iOSDevices.Count -FontSize 48 -FontWeight bold -Color Green -Alignment center
                }
                New-HTMLColumn {
                    New-HTMLText -Text "Android" -FontSize 14 -FontWeight bold -Color Orange -Alignment center
                    New-HTMLText -Text $AndroidDevices.Count -FontSize 48 -FontWeight bold -Color Orange -Alignment center
                }
                New-HTMLColumn {
                    New-HTMLText -Text "Linux" -FontSize 14 -FontWeight bold -Color Red -Alignment center
                    New-HTMLText -Text $LinuxDevices.Count -FontSize 48 -FontWeight bold -Color Red -Alignment center
                }
            }
        }

        # Inactive Devices for more thatn 30 days
        New-HTMLInfoCard -Title "Inactive Devices for more thatn 30 days" -Number $InactiveDevices.Count -Icon "✖️" -IconColor purple

        # Devices with low storage (Less than 100 GB)
        New-HTMLInfoCard -Title "Devices with low storage (Less than 100 GB)" -Number $LowStorageDevices.Count -Icon "💽" -IconColor "#ffc107"
        
    }
    # --------------------------------- Graphic Section 1 ---------------------------------------------------------------------------------------
    New-HTMLSection -Height 350 -HeaderText "Security & Compliance"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse  {
        
        # Security Status
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                New-ChartDonut -Name "Antivirus Enabled" -Value $ProtectedDevices.Count -Color "#28a745"
                New-ChartDonut -Name "Antivirus Disabled" -Value $UnprotectedDevices.Count  -Color "#dc3545"
            } -Title "Security Status" -TitleAlignment center
        }

        # Compliant Devices
        New-HTMLPanel {
            New-HTMLChart -Gradient {

                New-ChartDonut -Name  "Compliant Devices" -Value $CompliantDevices.Count -Color "#6f42c1"
                New-ChartDonut -Name  "Noncompliant Devices" -Value $NoncompliantDevices.Count -Color "#ffc107"

            } -Title "Compliance Status" -TitleAlignment center
        }
        
        # Devices with BitLocker Enabled
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                New-ChartDonut -Name "BitLocker Enabled" -Value $EncryptedDevices.Count -Color "#28a745"
                New-ChartDonut -Name "BitLocker Disabled" -Value $UnecryptedDevices.Count -Color "#dc3545"
            } -Title "BitLocker Status" -TitleAlignment center
        }
        
        # Azure Registred Device
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                New-ChartDonut -Name "Azure Registred Devices" -Value $AzureRegistredDevices.Count -Color "#00ccff"
                New-ChartDonut -Name "Azure Unregistred Devices" -Value $AzureUnregistredDevices.count  -Color "#0000cd"
            } -Title "Azure Registred Devices" -TitleAlignment center
        }
        
    }

    # --------------------------------- Graphic Section 2 ---------------------------------------------------------------------------------------
    New-HTMLSection -Height 350 -HeaderText "System & Hardware Insights" -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse  {

        # PC Manufactor
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                foreach($PC in $Manufactor) {
                    New-ChartBar -Name $PC.Name -Value $PC.Count 
                }
                New-ChartLegend -Name "Manufactor", "Number of Devices" 
            } -Title "TOP 10 Manufactors ( HP / DELL ... etc )" -TitleAlignment center
        }

        # Windows OS Version
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                foreach($OS in $OSVersions) {
                    New-ChartBar -Name $OS.Name -Value $OS.Count
                }
                New-ChartLegend -Name "OS Version", "Number of Users" 
            } -Title "TOP 10 Windows OS Versions" -TitleAlignment center
        }

        # Company / Personal Devices
        New-HTMLPanel {
            New-HTMLChart -Gradient {
                New-ChartDonut -Name "Company Devices" -Value $CompanyDevices.Count -Color "#add8e6" 
                New-ChartDonut -Name "Personal Devices" -Value $PersonalDevices.count  -Color "#00008b"
            } -Title "Company / Personal Devices" -TitleAlignment center
        }

    }

    # --------------------------------- DataTable Section ---------------------------------------------------------------------------------------    
    # Antivirus disabled Devices
    New-HTMLSection -HeaderText "Antivirus disabled"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($UnprotectedDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState) -Filtering -PagingLength 50
    }

    # Noncompliant Devices
    New-HTMLSection -HeaderText "Noncompliant Devices"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($NoncompliantDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState) -Filtering -PagingLength 50
    }
    
    # BitLocker disabled Devices
    New-HTMLSection -HeaderText "BitLocker disabled"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($UnecryptedDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState) -Filtering -PagingLength 50
    }

    # Azure Unregistred Devices
    New-HTMLSection -HeaderText "Azure Unregistred Devices"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($AzureUnregistredDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState ) -Filtering -PagingLength 50
    }

    # Personal Devices
    New-HTMLSection -HeaderText "Personal Devices"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($PersonalDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState ) -Filtering -PagingLength 50
    }

    # Inactive Devices
    New-HTMLSection -HeaderText "Inactive Devices"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($InactiveDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime | Sort-Object -Descending ComplianceState) -Filtering -PagingLength 50
    }

    # Devices with low storage
    New-HTMLSection -HeaderText "Devices with low storage"  -HeaderTextSize 14  -HeaderBackGroundColor "#708090" -CanCollapse {
        New-HTMLTable -DataTable ($LowStorageDevices | Select-Object DeviceName , UserPrincipalName , OperatingSystem, Manufacturer, Model, OSVersion, ComplianceState, IsEncrypted, LastSyncDateTime, EnrolledDateTime, @{Name="FreeSpaceGB";Expression={[math]::Round($_.FreeStorageSpaceInBytes / 1GB, 2)}} | Sort-Object -Descending ComplianceState) -Filtering -PagingLength 50
    }

} -ShowHTML


