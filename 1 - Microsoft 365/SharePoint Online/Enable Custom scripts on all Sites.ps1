Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

Import-Module Microsoft.Online.SharePoint.PowerShell

# Frame Tenant Admin URL from Tenant URL
$TenantAdminURL = "https://domain-admin.sharepoint.com/"

# Connect to SharePoint Online Tenant Admin portal
Connect-SPOService -URL $TenantAdminURL

# Get all SharePoint Online sites
$Sites = Get-SPOSite -Limit All

# Activate Custom Script on each site
foreach ($Site in $Sites) {
    Write-Host "Activation des Custom Scripts sur : $($Site.Url)" -ForegroundColor Cyan
    Set-SPOSite -Identity $Site.Url -DenyAddAndCustomizePages 0
}

Write-Host "✅ Custom Scripts enabled on all sites !" -ForegroundColor Green
