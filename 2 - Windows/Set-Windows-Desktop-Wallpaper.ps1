# This script is used to download Corporate Desktop Wallpaper from public https link then set this image as Desktop wallpaper
# I'm using this script with my Intune devices and with my RMM solution (NinjaOne), very reliable
# You need just to change the first variable value with your image link and enjoy the script.........

# ----------------------------- Change this variable with your image link -------------------------------------------
# direct link to download Background image
$Backgroundlink = "<Shared SharePoint Link or Public link for background image>"
# -------------------------------------------------------------------------------------------------------------------

$DownloadDir = "C:\Background\"
if((Test-Path $DownloadDir) -eq $false)
{
    New-Item -ItemType Directory -Path $DownloadDir -erroraction SilentlyContinue | Out-Null
}

# direct local path in the device to store downloaded Background image
$Download = $DownloadDir + "Background-img.png"

# function to Download the background
Invoke-WebRequest $Backgroundlink -OutFile $Download

# Function to set Image as desktop wallpaper
Function Set-WallPaper($Image) 
{  
Add-Type -TypeDefinition @" 
using System; 
using System.Runtime.InteropServices;
  
public class Params
{ 
    [DllImport("User32.dll",CharSet=CharSet.Unicode)] 
    public static extern int SystemParametersInfo (Int32 uAction, 
                                                   Int32 uParam, 
                                                   String lpvParam, 
                                                   Int32 fuWinIni);
}
"@ 
    $SPI_SETDESKWALLPAPER = 0x0014
    $UpdateIniFile = 0x01
    $SendChangeEvent = 0x02
    $fWinIni = $UpdateIniFile -bor $SendChangeEvent
    $ret = [Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Image, $fWinIni)
}
 
# Call previous function to set wallpaper
Set-WallPaper -Image $Download
