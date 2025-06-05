Set-Location HKLM:
Set-Location -Path "HKLM:\SOFTWARE\Policies\Microsoft"
if(!(Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"))
{
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name "PassportForWork" -Force
}

New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "DisablePostLogonProvisioning" -Value 0 -PropertyType DWORD -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "Enabled" -Value 0 -PropertyType DWORD -Force
