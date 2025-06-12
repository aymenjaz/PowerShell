
# Create temp folder under C:
$Dir = "C:\temp\" 
if((Test-Path $Dir) -eq $false)
{
    New-Item -ItemType Directory -Path $Dir -erroraction SilentlyContinue | Out-Null
}

# Giving Name to file to be downloaded
$Download = $Dir + "speedtest.zip"

# Download the SpeedTest file from official website
Invoke-WebRequest 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip' -OutFile $Download

# Unzip file
Expand-Archive $Download -DestinationPath "C:\temp\speedtest\"

# Execute speed test
$Speedtest = & "C:\temp\speedtest\speedtest.exe" --format=json --accept-license --accept-gdpr
Start-Sleep 3
# Convert result to Json
$Speedtest = $Speedtest | ConvertFrom-Json

# Create New Object SpeedObject
[PSCustomObject]$SpeedObject =[ordered] @{
    downloadspeed = [math]::Round($Speedtest.download.bandwidth / 1000000 * 8, 2)
    uploadspeed   = [math]::Round($Speedtest.upload.bandwidth / 1000000 * 8, 2)
    packetloss    = [math]::Round($Speedtest.packetLoss)
    Latency       = [math]::Round($Speedtest.ping.latency)
    isp           = $Speedtest.isp
    ExternalIP    = $Speedtest.interface.externalIp
    InternalIP    = $Speedtest.interface.internalIp
    UsedServer    = $Speedtest.server.host
    URL           = $Speedtest.result.url
    Jitter        = [math]::Round($Speedtest.ping.jitter)
    
}

Clear-Host
write-host
$SpeedObject
