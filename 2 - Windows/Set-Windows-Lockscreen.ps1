

# Download Directory for Lockscreen image file
$DownloadDir = "C:\Background\"

# Test if directory exist, otherwise create it
if((Test-Path $DownloadDir) -eq $false)
{
    New-Item -ItemType Directory -Path $DownloadDir -erroraction SilentlyContinue | Out-Null
}

# ----------------------------------------------------- This is the HTTPS link for the Lockscreen file URL
$Lockscreen = "<Shared SharePoint Link or Public link for background image>"

$Download = $DownloadDir + "Lockscreen-01.jpg"

# Download the Lockscreen
Invoke-WebRequest $Lockscreen -OutFile $Download


# Set Path for Lockscreen image
$LockscreenPath = "C:\Background\Lockscreen-01.jpg"

# Personalization registry Key
$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
if (!(Test-Path -Path $Key)) {
   New-Item -Path $Key -Force | Out-Null
}

# Set Lockscreen image
Set-ItemProperty -Path $Key -Name LockScreenImagePath -value $LockscreenPath
