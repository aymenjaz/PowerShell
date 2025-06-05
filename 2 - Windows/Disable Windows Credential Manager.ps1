$Params = @{
    Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Name = "DisableDomainCreds"
    Value = 1
    Type = 'DWord'
}

if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa")) 
{
    New-Item -Path $regPath -Force | Out-Null
}

Set-ItemProperty @Params
