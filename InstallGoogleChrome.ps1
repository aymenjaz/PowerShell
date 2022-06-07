# this script allows to download and install automatically google chrome


# Create a temporary directory to store Google Chrome.
mkdir -Path $env:temp\chromeinstall -erroraction SilentlyContinue | Out-Null
$Download = join-path $env:temp\chromeinstall chrome_installer.exe

# Download the Google Chrome installer.
Invoke-WebRequest 'http://dl.google.com/chrome/install/375.126/chrome_installer.exe'  -OutFile $Download

# Install Google Chrome using Powershell.
Invoke-Expression "$Download /install"
