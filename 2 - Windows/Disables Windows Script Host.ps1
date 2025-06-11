$path = "HKLM:\Software\Microsoft\Windows Script Host\Settings"
if (-not (Test-Path $path)) {
    New-Item -Path $path -Force | Out-Null
}
Set-ItemProperty -Path $path -Name "Enabled" -Value 0 -Type DWord
