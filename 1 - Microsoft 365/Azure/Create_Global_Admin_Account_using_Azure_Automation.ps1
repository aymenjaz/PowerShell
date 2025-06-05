# This code is to use with Azure Automation Account to create Global Admin
# I have used this code with azure webhook to remotely create global Admin if my global admin account is compromised
# Login and password here is fake and just for learning purposes

try {
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Import necessary modules
Import-Module Az.Accounts
Import-Module Az.Resources

# Get Azure AD token
$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.microsoft.com").AccessToken

# Define variables
$userUPN = "BreakGlass@globalitnow.onmicrosoft.com"
$userDisplayName = "BG Global Admin"
$password = "P@ssw0rd123!"

# Create the new user
$uri = "https://graph.microsoft.com/v1.0/users"
$body = @{
    accountEnabled = $true
    displayName = $userDisplayName
    mailNickname = ($userUPN -split '@')[0]
    userPrincipalName = $userUPN
    passwordProfile = @{
        password = $password
        forceChangePasswordNextSignIn = $true
    }
} | ConvertTo-Json

$newUser = Invoke-RestMethod -Uri $uri -Headers @{Authorization = "Bearer $token"} -Method Post -Body $body -ContentType "application/json"

# Get Global Administrator role
$uri = "https://graph.microsoft.com/v1.0/directoryRoles"
$roles = Invoke-RestMethod -Uri $uri -Headers @{Authorization = "Bearer $token"} -Method Get
$globalAdminRole = $roles.value | Where-Object { $_.displayName -eq 'Global Administrator' }

# Assign Global Administrator role to the new user
$uri = "https://graph.microsoft.com/v1.0/directoryRoles/$($globalAdminRole.id)/members/`$ref"
$body = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($newUser.id)"
} | ConvertTo-Json

Invoke-RestMethod -Uri $uri -Headers @{Authorization = "Bearer $token"} -Method Post -Body $body -ContentType "application/json"

Write-Output "New Global Administrator user created successfully: $userUPN"
