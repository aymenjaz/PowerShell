# Enable Windows Firewall (domain + private + public)
# Open PowerShell as administrator to run these commands

try
{
# Enable firewall for domain profile
Set-NetFirewallProfile -Profile Domain -Enabled True
Write-Host "Windows Domain Firewall activated successfully" -ForegroundColor Green
}
catch{Write-Host "Error while enabling Windows Domain Firewall" -ForegroundColor Red}

try
{
# Enable firewall for private profile
Set-NetFirewallProfile -Profile Private -Enabled True
Write-Host "Windows Private Firewall activated successfully" -ForegroundColor Green
}
catch{Write-Host "Error while enabling Windows Private Firewall" -ForegroundColor Red}

try
{
# Enable firewall for public profile
Set-NetFirewallProfile -Profile Public -Enabled True
Write-Host "Windows Public Firewall activated successfully" -ForegroundColor Green
}
catch{Write-Host "Error while enabling Windows Public Firewall" -ForegroundColor Red}

