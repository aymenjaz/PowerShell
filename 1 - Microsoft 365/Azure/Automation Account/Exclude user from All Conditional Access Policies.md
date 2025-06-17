
# 🚨 Conditional Access Emergency Bypass via Webhook

This project provides a PowerShell-based automated recovery mechanism that allows administrators to **exclude a specific user from all Conditional Access (CA) policies** in Microsoft Entra (Azure AD), using an **HTTP-triggered Azure Automation Runbook**.  
It's designed to **unlock admin access** in the event of a misconfigured or overly strict CA policy blocking login.

---

## 🔧 Use Case

Sometimes, a Conditional Access policy might unintentionally block administrators from accessing Microsoft 365 services (e.g. due to missing conditions, MFA misconfigurations, or IP restrictions). This script provides a secure way to **remotely exclude an emergency account** from all CA policies via a **simple HTTP POST request**, restoring access quickly without requiring external help.

---

## 📌 How It Works

1. **Azure Automation Runbook** runs a PowerShell script that:
   - Reads the user to exclude from a JSON body (`$WebhookData`)
   - Authenticates to Microsoft Graph using an App Registration
   - Retrieves all Conditional Access policies
   - Adds the specified user to the exclusion list of each CA policy

2. A **Webhook URL** is generated for the Runbook.

3. An **external PowerShell script** or other service can trigger the webhook with the target user UPN to restore access.

---

## 🧰 Requirements

- Azure Automation Account
- App Registration with:
  - Microsoft Graph permissions:
    - `Policy.ReadWrite.ConditionalAccess`
    - `User.Read.All`
  - Client Secret
- The App Registration must be granted **admin consent**
- User account to be excluded must already exist in Entra ID

---

## 🧪 Script 1 – Azure Automation Runbook

This script is triggered via a webhook and takes a JSON payload with the user UPN to exclude.

```powershell
# User to exclude from all CA Policies
param(
    [object]$WebhookData
)

# Extract JSON body
if ($WebhookData -ne $null) {
    $body = $WebhookData.RequestBody | ConvertFrom-Json
    $UserToExclude = $body.UserToExclude
    Write-Output "User to exclude : $UserToExclude"
} else {
    Write-Error "WebhookData is null"
    exit
}


# ----------------------------
# Define your app credentials
# ----------------------------
$TenantId     = "xxxxxx-xxxxxxx-xxxxxxx-xxxxxxx-xxxxxxx"  # entra tenant ID
$ClientId     = "xxxxxx-xxxxxxx-xxxxxxx-xxxxxxx-xxxxxxx"  # entra application ID
$ClientSecret = "xxxxxx-xxxxxxx-xxxxxxx-xxxxxxx-xxxxxxx"  # entra application secret

$Scope        = "https://graph.microsoft.com/.default"
$AuthUrl      = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

# ========== Build Body ==========
$Body = @{
    client_id     = $ClientId
    scope         = $Scope
    client_secret = $ClientSecret
    grant_type    = "client_credentials"
}

# ========== Request Access Token ==========
$TokenResponse = Invoke-RestMethod -Method POST -Uri $AuthUrl -Body $Body -ContentType "application/x-www-form-urlencoded"
$AccessToken   = $TokenResponse.access_token

# ========== Use Access Token in API Call ==========
$Headers = @{
    Authorization = "Bearer $AccessToken"
}

# ===============================
# GET USER OBJECT ID
# ===============================
$UserResponse = Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserToExclude" -Headers $Headers
$UserId = $UserResponse.id

# ===============================
# GET ALL CONDITIONAL ACCESS POLICIES
# ===============================
$PoliciesResponse = Invoke-RestMethod -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -Headers $Headers
$Policies = $PoliciesResponse.value

# ===============================
# EXCLUDE USER FROM ALL CONDITIONAL ACCESS POLICIES
# ===============================
foreach ($Policy in $Policies) {
    Write-Output "Processing policy: $($Policy.displayName)"

    $Conditions = $Policy.conditions
    if (-not $Conditions.users) {
        Write-Output "Policy has no user condition, skipping..."
        continue
    }

    $IncludeUsers = $Conditions.users.includeUsers
    $ExcludeUsers = $Conditions.users.excludeUsers

    if ($ExcludeUsers -contains $UserId) {
        Write-Output "User already excluded, skipping..."
        continue
    }

    # Add the user to the exclusion list
    $NewExcludeList = $ExcludeUsers + $UserId

    # Reconstruct the conditions object
    $NewConditions = @{
        users = @{
            includeUsers = $IncludeUsers
            excludeUsers = $NewExcludeList
        }
    }

    # Update the policy
    $UpdateUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($Policy.id)"
    $Body = @{
        conditions = $NewConditions
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Method PATCH -Uri $UpdateUri `
    -Headers @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    } `
    -Body $Body

    Write-Output "User excluded from policy: $($Policy.displayName)"
}

# ===============================
# REMOVE TOKEN
# ===============================
Remove-Variable AccessToken, ClientSecret, TokenResponse, Headers, PatchHeaders -ErrorAction SilentlyContinue
````

---

## 🚀 Script 2 – Webhook Trigger Example

This script triggers the Azure Automation Runbook webhook and passes the user UPN to be excluded.

```powershell
# Define User to Exclude from Conditional Access
$UserToExclude = "user@domain.com"

# Replace with your actual webhook URL
$webhookUrl = "https://YOUR-WEBHOOK-URL"

# Trigger webhook
Invoke-RestMethod -Uri $webhookUrl -Method Post -Body (@{ UserToExclude = $($UserToExclude) } | ConvertTo-Json) -ContentType 'application/json'
```

---

## 🔐 Security Considerations

* Store your App Secret securely (use Key Vault in production).
* Ensure the webhook URL is not publicly exposed or shared.
* Consider time-limiting the webhook's usage or restricting execution permissions.

---

## ✅ Best Practices

* Create a dedicated **break-glass account** and test this automation beforehand.
* Enable **logging** in the Runbook for audit purposes.
* Document this emergency process internally for your IT team.

---

## 📄 License

MIT License

---

## 🙌 Credits

Created by [Aymen EL JAZIRI](https://www.linkedin.com/in/aymeneljaziri) — for the Microsoft 365 & Intune community.


