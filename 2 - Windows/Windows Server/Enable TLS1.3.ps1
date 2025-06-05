
# enable it using registry for the server:

Set-Location HKLM:
$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server"
$TempPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
if(Test-Path $RegPath)
{
    $Items = Get-Item $RegPath | Select-Object Property
    if($Items.Property -contains "DisabledByDefault")
    {
        Set-ItemProperty -Path $RegPath -Name "DisabledByDefault" -Value 0
    }
    else 
    {
        New-ItemProperty -Path $RegPath -Name "DisabledByDefault" -PropertyType "DWORD"  -Value 0
    }
    if($Items.Property -contains "Enabled")
    {
        Set-ItemProperty -Path $RegPath -Name "Enabled" -Value 1
    }
    else 
    {
        New-ItemProperty -Path $RegPath -Name "Enabled" -PropertyType "DWORD"  -Value 1
    }
    
}
elseif(Test-Path $TempPath) 
{
    Set-Location $TempPath
    New-Item -Name "TLS 1.3"
    New-Item -Path ($TempPath+"\TLS 1.3") -Name "Server"
    Set-Location $RegPath
    New-ItemProperty -Path $RegPath -Name "DisabledByDefault" -PropertyType "DWORD"  -Value 0
    New-ItemProperty -Path $RegPath -Name "Enabled" -PropertyType "DWORD"  -Value 1
}
