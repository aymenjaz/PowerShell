# Create a temporary directory to store PSTools
$Dir = "C:\temp\" 
if((Test-Path $Dir) -eq $false)
{
    New-Item -ItemType Directory -Path $Dir -erroraction SilentlyContinue | Out-Null
}

$Download = $Dir + "PSTools.zip"

# Download the PSTools
Invoke-WebRequest 'https://download.sysinternals.com/files/PSTools.zip' -OutFile $Download

# Unzip downloaded file
Expand-Archive $Download -DestinationPath "C:\temp\PsTools\" 

# Run exe
Invoke-Expression -Command "C:\temp\PsTools\psexec.exe -s -i -d regedit" 
