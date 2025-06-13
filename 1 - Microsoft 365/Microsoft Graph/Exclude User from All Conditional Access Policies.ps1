# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Identity.SignIns
Import-Module Microsoft.Graph.Users


# Connect to Microsoft Graph with the required scope
Connect-MgGraph -Scopes "User.Read.All", "Policy.ReadWrite.ConditionalAccess"

# Set the user principal name (UPN) of the user to exclude
$UserToExclude = "user1@domain.com"

# Get the object ID of the user
$User = Get-MgUser -UserId $UserToExclude
$UserId = $User.Id

# Get all Conditional Access Policies
$Policies = Get-MgIdentityConditionalAccessPolicy

foreach ($Policy in $Policies) 
{
    Write-Output "Processing policy: $($Policy.DisplayName)"

    # Skip if Users condition is missing
    if (-not $Policy.Conditions.Users) 
    {
        Write-Output "Policy has no user condition, skipping..."
        continue
    }

    # If the user is already excluded, skip
    if ($ExcludeUsers -contains $UserId) 
    {
        Write-Output "User already excluded, skipping..."
        continue
    }

    $IncludeUsers = $Policy.Conditions.Users.IncludeUsers
    $ExcludeUsers = $Policy.Conditions.Users.ExcludeUsers

    # Add user ID to exclusion list
    $NewExcludeList = $ExcludeUsers + $UserId

    # Build new Users condition
    $NewUsersCondition = @{
        IncludeUsers = $IncludeUsers
        ExcludeUsers = $NewExcludeList
    }

    # Create new Conditions object with updated Users
    $NewConditions = @{
        Users = $NewUsersCondition
    }

    # Apply the update to the policy
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $Policy.Id -Conditions $NewConditions

    Write-Output "User excluded from policy: $($Policy.DisplayName)"
}

Disconnect-MgGraph
