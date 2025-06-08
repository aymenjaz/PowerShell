# ==========================================================================================================
# Script to remove a specified user from all Distribution Groups and Microsoft 365 Groups in Exchange Online
# Requirements:
#   - ExchangeOnlineManagement module must be installed
#   - You must be connected to Exchange Online (automatically handled in script)
# ==========================================================================================================

# ----------------------------------------
# Function: Connect-ToExchangeOnline
# ----------------------------------------
# - Installs ExchangeOnlineManagement module if missing
# - Imports module
# - Connects to Exchange Online
function Connect-ToExchangeOnline {
    if (!(Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "The ExchangeOnlineManagement module is not installed. Installation in progress..." -ForegroundColor Yellow
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
    }

    Import-Module ExchangeOnlineManagement
    Connect-ExchangeOnline
}

# ----------------------------------------
# Function: Remove-UserFromAllGroups
# ----------------------------------------
# Parameters:
#   -UserEmail : User's email address (required)
# Description:
#   - Checks if the user exists
#   - Searches for all Distribution Groups and M365 Groups
#   - Removes the user from any group where they are a member
function Remove-UserFromAllGroups {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserEmail
    )

    # --- Validate that the user exists in Exchange ---
    try {
        $user = Get-EXOMailbox -Identity $UserEmail -ErrorAction Stop
        Write-Host "User found : $($user.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "The user with the email address $UserEmail was not found." -ForegroundColor Red
        return
    }

    # --- Retrieve all groups ---
    Write-Host "Search for distribution groups..." -ForegroundColor Yellow
    $distributionGroups = Get-DistributionGroup -ResultSize Unlimited

    Write-Host "Search for Microsoft 365 groups..." -ForegroundColor Yellow
    $m365Groups = Get-UnifiedGroup -ResultSize Unlimited

    # --- Initialize counters and logs ---
    $removedFromCount = 0
    $errorCount = 0
    $groupsList = @()

    # --- Remove from Distribution Groups ---
    foreach ($group in $distributionGroups) {
        try {
            $groupMembers = Get-DistributionGroupMember -Identity $group.Identity -ResultSize Unlimited
            if ($groupMembers.PrimarySmtpAddress -contains $UserEmail) {
                Write-Host "Remove user from distribution group : $($group.DisplayName)" -ForegroundColor Yellow
                Remove-DistributionGroupMember -Identity $group.Identity -Member $UserEmail -Confirm:$false
                $removedFromCount++
                $groupsList += "Distribution: $($group.DisplayName)"
            }
        } catch {
            Write-Host "Error verifying/deleting user from group $($group.DisplayName): $_" -ForegroundColor Red
            $errorCount++
        }
    }

    # --- Remove from Microsoft 365 Groups ---
    foreach ($group in $m365Groups) {
        try {
            $groupMembers = Get-UnifiedGroupLinks -Identity $group.Identity -LinkType Members -ResultSize Unlimited
            if ($groupMembers.PrimarySmtpAddress -contains $UserEmail) {
                Write-Host "Remove user from Microsoft 365 group : $($group.DisplayName)" -ForegroundColor Yellow
                Remove-UnifiedGroupLinks -Identity $group.Identity -LinkType Members -Links $UserEmail -Confirm:$false
                $removedFromCount++
                $groupsList += "Microsoft 365: $($group.DisplayName)"
            }
        } catch {
            Write-Host "Error verifying/deleting user from group $($group.DisplayName): $_" -ForegroundColor Red
            $errorCount++
        }
    }

    # --- Final Summary ---
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "User : $($user.DisplayName) ($UserEmail)" -ForegroundColor Cyan
    Write-Host "Deleted from $removedFromCount groups" -ForegroundColor Green
    Write-Host "Errors encountered : $errorCount" -ForegroundColor Cyan

    if ($groupsList.Count -gt 0) {
        Write-Host "`nRemoved user groups :" -ForegroundColor Green
        $groupsList | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
    }
}

# ----------------------------------------
# MAIN SCRIPT EXECUTION
# ----------------------------------------
# Connect to Exchange Online
Connect-ToExchangeOnline

# Define the target user
$UserEmailAddress = "user1@domain.com"

# Remove the user from all Exchange Online groups
Remove-UserFromAllGroups -UserEmail $UserEmailAddress
