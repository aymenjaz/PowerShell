<#
.SYNOPSIS
    Audits every application in a Microsoft Entra ID tenant (App Registrations, Enterprise Apps,
    Managed Identities) and produces a risk-scored HTML report.

.DESCRIPTION
    Invoke-EntraAppRiskAudit.ps1 collects, in read-only mode, through Microsoft Graph:
      - Application objects (App Registrations): requested permissions, secrets, certificates,
        federated identity credentials, redirect URIs, implicit grant, owners
      - Service principals (Enterprise Apps, third-party apps, Managed Identities):
        granted application permissions (appRoleAssignments), granted delegated permissions
        (oauth2PermissionGrants), credentials added directly on the SP, owners
      - Entra ID directory role assignments held by service principals
      - Optional: last sign-in activity per service principal (Entra ID P1/P2 required)

    Each application receives a multi-factor risk score (0-100) and a level:
      Critical / High / Medium / Low / Secure

    Outputs (in -OutputPath):
      - EntraAppAudit_<date>.html        Self-contained interactive report
      - EntraAppAudit_<date>_Apps.csv    One line per application
      - EntraAppAudit_<date>_Credentials.csv
      - EntraAppAudit_<date>_Permissions.csv
      - EntraAppAudit_<date>.json        Full dataset (for run-to-run comparison)

.PARAMETER OutputPath
    Folder where the report files are written. Created if missing.

.PARAMETER IncludeMicrosoftApps
    Include Microsoft first-party service principals (excluded by default, they add hundreds of
    entries with no actionable value).

.PARAMETER IncludeSignInActivity
    Query /beta/reports/servicePrincipalSignInActivities to flag inactive apps.
    Requires Entra ID P1/P2 and AuditLog.Read.All.

.PARAMETER InactiveDays
    Number of days without sign-in after which an app with permissions is flagged as inactive.

.PARAMETER ExpiryCriticalDays / ExpiryWarningDays / ExpiryNoticeDays
    Credential expiry thresholds (default 30 / 60 / 90 days).

.PARAMETER TenantId / ClientId / CertificateThumbprint
    App-only authentication with a certificate (unattended / scheduled runs).

.PARAMETER UseManagedIdentity
    Authenticate with the managed identity of the host (Azure Automation, Azure VM, Functions).

.EXAMPLE
    .\Invoke-EntraAppRiskAudit.ps1 -OutputPath C:\Reports -IncludeSignInActivity

.EXAMPLE
    .\Invoke-EntraAppRiskAudit.ps1 -TenantId contoso.onmicrosoft.com -ClientId <appId> `
        -CertificateThumbprint <thumbprint> -IncludeSignInActivity

.NOTES
    Author        : CloudSecOp.com
    Requirements  : PowerShell 7.2+, Microsoft.Graph.Authentication module (2.x)
    Delegated     : Application.Read.All, Directory.Read.All, RoleManagement.Read.Directory,
                    AuditLog.Read.All (only with -IncludeSignInActivity)
                    Recommended role for the operator: Global Reader
    App-only      : same permissions as Application permissions, admin consented
    The script is strictly read-only: it never modifies the tenant.
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [string]$OutputPath = (Join-Path -Path (Get-Location) -ChildPath 'EntraAppAudit'),

    [switch]$IncludeMicrosoftApps,
    [switch]$IncludeSignInActivity,

    [ValidateRange(7, 730)]
    [int]$InactiveDays = 90,

    [ValidateRange(1, 365)]
    [int]$ExpiryCriticalDays = 30,
    [ValidateRange(1, 365)]
    [int]$ExpiryWarningDays = 60,
    [ValidateRange(1, 365)]
    [int]$ExpiryNoticeDays = 90,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AppOnly', Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory)]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
    [switch]$UseManagedIdentity
)

#Requires -Version 7.2
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

#region ===================== Risk catalog =====================

# Tier: Critical = tenant takeover or code execution at scale
#       High     = mass access to business data
#       Medium   = sensitive but limited, or reconnaissance at scale
#       Low      = limited impact
# Weight applies to APPLICATION permissions. Delegated permissions are weighted down
# (x0.5 when consented for all users, x0.3 when consented by individual users).
$script:PermissionCatalog = @{
    # ---- Tenant takeover / privilege escalation ----
    'RoleManagement.ReadWrite.Directory'                 = @{ Tier = 'Critical'; Weight = 60; Reason = 'Can assign any Entra ID role, including Global Administrator' }
    'AppRoleAssignment.ReadWrite.All'                    = @{ Tier = 'Critical'; Weight = 60; Reason = 'Can grant itself any application permission (self-escalation)' }
    'Application.ReadWrite.All'                          = @{ Tier = 'Critical'; Weight = 55; Reason = 'Can add credentials to any app and impersonate it' }
    'Application.ReadWrite.OwnedBy'                      = @{ Tier = 'Medium';   Weight = 15; Reason = 'Can manage credentials of the apps it owns' }
    'Directory.ReadWrite.All'                            = @{ Tier = 'Critical'; Weight = 55; Reason = 'Write access to the whole directory' }
    'RoleAssignmentSchedule.ReadWrite.Directory'         = @{ Tier = 'Critical'; Weight = 55; Reason = 'Can create active PIM role assignments' }
    'RoleEligibilitySchedule.ReadWrite.Directory'        = @{ Tier = 'Critical'; Weight = 50; Reason = 'Can create eligible PIM role assignments' }
    'PrivilegedAccess.ReadWrite.AzureADGroup'            = @{ Tier = 'Critical'; Weight = 45; Reason = 'Can manage PIM for Groups membership' }
    'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'= @{ Tier = 'Critical'; Weight = 45; Reason = 'Can activate PIM for Groups assignments' }
    'UserAuthenticationMethod.ReadWrite.All'             = @{ Tier = 'Critical'; Weight = 50; Reason = 'Can add a Temporary Access Pass or MFA method to any user (account takeover)' }
    'Domain.ReadWrite.All'                               = @{ Tier = 'Critical'; Weight = 50; Reason = 'Can federate a domain and forge tokens (Golden SAML style attack)' }
    'Policy.ReadWrite.ConditionalAccess'                 = @{ Tier = 'Critical'; Weight = 45; Reason = 'Can disable or bypass Conditional Access policies' }
    'Policy.ReadWrite.AuthenticationMethod'              = @{ Tier = 'Critical'; Weight = 40; Reason = 'Can weaken tenant authentication methods policy' }
    'Policy.ReadWrite.PermissionGrant'                   = @{ Tier = 'Critical'; Weight = 40; Reason = 'Can change who is allowed to consent to applications' }
    'Organization.ReadWrite.All'                         = @{ Tier = 'High';     Weight = 30; Reason = 'Can modify tenant-wide settings (including certificate-based authentication)' }
    'User.ReadWrite.All'                                 = @{ Tier = 'High';     Weight = 30; Reason = 'Can modify any non-admin user account' }
    'Group.ReadWrite.All'                                = @{ Tier = 'High';     Weight = 30; Reason = 'Can modify any group, including groups granting access to resources' }
    'GroupMember.ReadWrite.All'                          = @{ Tier = 'High';     Weight = 30; Reason = 'Can add members to groups granting access to resources' }
    'ServicePrincipalEndpoint.ReadWrite.All'             = @{ Tier = 'Medium';   Weight = 15; Reason = 'Can modify service principal endpoints' }

    # ---- Code execution on endpoints (Intune) ----
    'DeviceManagementConfiguration.ReadWrite.All'        = @{ Tier = 'Critical'; Weight = 50; Reason = 'Can deploy PowerShell scripts and remediations to every managed device' }
    'DeviceManagementApps.ReadWrite.All'                 = @{ Tier = 'Critical'; Weight = 45; Reason = 'Can deploy arbitrary applications to every managed device' }
    'DeviceManagementRBAC.ReadWrite.All'                 = @{ Tier = 'Critical'; Weight = 45; Reason = 'Can grant itself Intune administrative roles' }
    'DeviceManagementManagedDevices.PrivilegedOperations.All' = @{ Tier = 'Critical'; Weight = 40; Reason = 'Can wipe, retire or reset devices at scale' }
    'DeviceManagementManagedDevices.ReadWrite.All'       = @{ Tier = 'High';     Weight = 25; Reason = 'Can modify managed devices' }
    'DeviceManagementServiceConfig.ReadWrite.All'        = @{ Tier = 'High';     Weight = 25; Reason = 'Can modify Intune service configuration (enrollment, connectors)' }

    # ---- Mail / Exchange ----
    'full_access_as_app'                                 = @{ Tier = 'Critical'; Weight = 55; Reason = 'Full EWS access to every mailbox in the organization' }
    'Exchange.ManageAsApp'                               = @{ Tier = 'High';     Weight = 35; Reason = 'Exchange Online PowerShell as application (impact depends on assigned Exchange role)' }
    'Mail.ReadWrite'                                     = @{ Tier = 'High';     Weight = 40; Reason = 'Read and modify every mailbox' }
    'Mail.Send'                                          = @{ Tier = 'High';     Weight = 40; Reason = 'Send mail as any user (internal phishing, BEC)' }
    'Mail.Read'                                          = @{ Tier = 'High';     Weight = 35; Reason = 'Read every mailbox' }
    'MailboxSettings.ReadWrite'                          = @{ Tier = 'High';     Weight = 25; Reason = 'Can create forwarding and inbox rules on any mailbox' }
    'EWS.AccessAsUser.All'                               = @{ Tier = 'High';     Weight = 35; Reason = 'Full EWS access with the signed-in user identity' }
    'Mail.ReadBasic.All'                                 = @{ Tier = 'Medium';   Weight = 12; Reason = 'Read mail metadata of every mailbox' }
    'Calendars.ReadWrite'                                = @{ Tier = 'Medium';   Weight = 18; Reason = 'Read and modify every calendar' }
    'Calendars.Read'                                     = @{ Tier = 'Medium';   Weight = 12; Reason = 'Read every calendar' }
    'Contacts.ReadWrite'                                 = @{ Tier = 'Medium';   Weight = 12; Reason = 'Read and modify every contact list' }

    # ---- Files / SharePoint / OneDrive ----
    'Sites.FullControl.All'                              = @{ Tier = 'Critical'; Weight = 50; Reason = 'Full control of every SharePoint site and OneDrive' }
    'Sites.Manage.All'                                   = @{ Tier = 'High';     Weight = 40; Reason = 'Manage every SharePoint site' }
    'Sites.ReadWrite.All'                                = @{ Tier = 'High';     Weight = 40; Reason = 'Read and write every SharePoint site and OneDrive' }
    'Files.ReadWrite.All'                                = @{ Tier = 'High';     Weight = 40; Reason = 'Read and write every file in the tenant' }
    'Sites.Read.All'                                     = @{ Tier = 'High';     Weight = 30; Reason = 'Read every SharePoint site and OneDrive' }
    'Files.Read.All'                                     = @{ Tier = 'High';     Weight = 30; Reason = 'Read every file in the tenant' }
    'Sites.Selected'                                     = @{ Tier = 'Low';      Weight = 4;  Reason = 'Scoped to explicitly granted sites (recommended pattern)' }
    'Notes.ReadWrite.All'                                = @{ Tier = 'Medium';   Weight = 18; Reason = 'Read and write every OneNote notebook' }

    # ---- Teams ----
    'Chat.ReadWrite.All'                                 = @{ Tier = 'High';     Weight = 35; Reason = 'Read and write every Teams chat' }
    'Chat.Read.All'                                      = @{ Tier = 'High';     Weight = 30; Reason = 'Read every Teams chat' }
    'ChannelMessage.Read.All'                            = @{ Tier = 'High';     Weight = 30; Reason = 'Read every Teams channel message' }
    'TeamMember.ReadWrite.All'                           = @{ Tier = 'Medium';   Weight = 18; Reason = 'Add or remove members of any team' }

    # ---- Compliance / Security ----
    'eDiscovery.ReadWrite.All'                           = @{ Tier = 'High';     Weight = 35; Reason = 'Run eDiscovery searches and exports across the tenant' }
    'IdentityRiskyUser.ReadWrite.All'                    = @{ Tier = 'Medium';   Weight = 20; Reason = 'Can dismiss user risk (hide compromise signals)' }
    'SecurityEvents.ReadWrite.All'                       = @{ Tier = 'Medium';   Weight = 15; Reason = 'Can modify security alerts' }
    'SecurityIncident.ReadWrite.All'                     = @{ Tier = 'Medium';   Weight = 15; Reason = 'Can modify or close security incidents' }

    # ---- Reconnaissance at scale ----
    'Directory.Read.All'                                 = @{ Tier = 'Medium';   Weight = 10; Reason = 'Read the whole directory (reconnaissance)' }
    'Directory.AccessAsUser.All'                         = @{ Tier = 'High';     Weight = 35; Reason = 'Same directory access as the signed-in user' }
    'User.Read.All'                                      = @{ Tier = 'Low';      Weight = 6;  Reason = 'Read all user profiles' }
    'Group.Read.All'                                     = @{ Tier = 'Low';      Weight = 6;  Reason = 'Read all groups' }
    'AuditLog.Read.All'                                  = @{ Tier = 'Low';      Weight = 6;  Reason = 'Read sign-in and audit logs' }
    'Policy.Read.All'                                    = @{ Tier = 'Low';      Weight = 5;  Reason = 'Read tenant policies (Conditional Access included)' }
    'DeviceManagementManagedDevices.Read.All'            = @{ Tier = 'Low';      Weight = 5;  Reason = 'Read all managed devices' }

    # ---- Azure Resource Manager ----
    'user_impersonation'                                 = @{ Tier = 'Medium';   Weight = 15; Reason = 'Acts as the user on the target API (Azure Resource Manager or other)' }
}

# Directory roles held by service principals
$script:RoleCatalog = @{
    'Global Administrator'                     = 70
    'Privileged Role Administrator'            = 70
    'Privileged Authentication Administrator'  = 65
    'Application Administrator'                = 60
    'Cloud Application Administrator'          = 60
    'Hybrid Identity Administrator'            = 55
    'Conditional Access Administrator'         = 55
    'Security Administrator'                   = 50
    'Intune Administrator'                     = 50
    'Exchange Administrator'                   = 50
    'SharePoint Administrator'                 = 45
    'User Administrator'                       = 40
    'Authentication Administrator'             = 40
    'Groups Administrator'                     = 35
    'Directory Writers'                        = 35
    'Helpdesk Administrator'                   = 30
}
$script:DefaultRoleWeight = 15

# Microsoft first-party tenants (appOwnerOrganizationId)
$script:MicrosoftTenantIds = @(
    'f8cddef3-2b74-4e19-a0a3-5d8c00c18be7',  # Microsoft Services
    '72f988bf-86f1-41af-91ab-2d7cd011db47',  # Microsoft corporate
    '33e01921-4d64-4f8c-a055-5bdaffd5e33d',  # Microsoft (Azure services)
    'cdc5aeea-15c5-4db6-b079-fcadd2505dc2'   # Microsoft (Dynamics / Power Platform)
)

# Score to level mapping
$script:LevelThresholds = [ordered]@{ Critical = 70; High = 45; Medium = 25; Low = 10; Secure = 0 }
$script:LevelRank       = @{ Secure = 0; Low = 1; Medium = 2; High = 3; Critical = 4 }

#endregion

#region ===================== Graph helpers =====================

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Cyan
}

function Invoke-GraphPaged {
    <# Follows @odata.nextLink until the collection is complete. #>
    param([Parameter(Mandatory)][string]$Uri)

    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($resp.PSObject.Properties['value'] -and $resp.value) {
            foreach ($item in $resp.value) { $results.Add($item) }
        }
        $next = if ($resp.PSObject.Properties['@odata.nextLink']) { $resp.'@odata.nextLink' } else { $null }
    }
    return , $results
}

function Invoke-GraphBatch {
    <#
        Sends GET requests through JSON batching (20 per call), retries throttled responses,
        and follows paging on each sub-response.
        Input : hashtable  key (request id) -> relative URL (e.g. /servicePrincipals/{id}/owners)
        Output: hashtable  key -> List[object] of collected items (empty list on 403/404)
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Requests,
        [string]$ApiVersion = 'v1.0',
        [string]$Activity = 'Graph batch'
    )

    $output  = @{}
    $pending = [System.Collections.Generic.Queue[string]]::new()
    foreach ($k in $Requests.Keys) { $pending.Enqueue([string]$k); $output[[string]$k] = [System.Collections.Generic.List[object]]::new() }

    $total = $pending.Count
    $done  = 0
    $attempts = @{}

    while ($pending.Count -gt 0) {
        $chunk = [System.Collections.Generic.List[string]]::new()
        while ($pending.Count -gt 0 -and $chunk.Count -lt 20) { $chunk.Add($pending.Dequeue()) }

        $body = @{
            requests = @($chunk | ForEach-Object { @{ id = $_; method = 'GET'; url = $Requests[$_] } })
        } | ConvertTo-Json -Depth 5

        $resp = Invoke-MgGraphRequest -Method POST -Uri "$ApiVersion/`$batch" -Body $body `
                    -ContentType 'application/json' -OutputType PSObject

        $maxRetryAfter = 0
        foreach ($r in $resp.responses) {
            $id = [string]$r.id
            switch ([int]$r.status) {
                { $_ -in 200..299 } {
                    $b = $r.body
                    if ($b.PSObject.Properties['value']) {
                        foreach ($item in $b.value) { $output[$id].Add($item) }
                        if ($b.PSObject.Properties['@odata.nextLink'] -and $b.'@odata.nextLink') {
                            foreach ($item in (Invoke-GraphPaged -Uri $b.'@odata.nextLink')) { $output[$id].Add($item) }
                        }
                    }
                    else { $output[$id].Add($b) }
                    $done++
                }
                { $_ -in 429, 503, 504 } {
                    $attempts[$id] = 1 + [int]($attempts[$id] ?? 0)
                    if ($attempts[$id] -le 6) {
                        $ra = 5
                        if ($r.PSObject.Properties['headers'] -and $r.headers -and $r.headers.PSObject.Properties['Retry-After']) {
                            $ra = [int]$r.headers.'Retry-After'
                        }
                        $maxRetryAfter = [Math]::Max($maxRetryAfter, $ra)
                        $pending.Enqueue($id)
                    }
                    else {
                        Write-Warning "Request $id still throttled after 6 attempts, skipped."
                        $done++
                    }
                }
                default {
                    # 403 / 404: object deleted or not readable, keep empty result
                    Write-Verbose "Batch request $id returned HTTP $($r.status)"
                    $done++
                }
            }
        }

        Write-Progress -Activity $Activity -Status "$done / $total" -PercentComplete ([Math]::Min(100, ($done / [Math]::Max(1, $total)) * 100))
        if ($maxRetryAfter -gt 0) {
            Write-Verbose "Throttled, waiting $maxRetryAfter s"
            Start-Sleep -Seconds $maxRetryAfter
        }
    }
    Write-Progress -Activity $Activity -Completed
    return $output
}

function ConvertTo-UtcDate {
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    try {
        return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    }
    catch { return $null }
}

function Get-Prop {
    <# Safe property read under StrictMode. #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

#endregion

#region ===================== Connection =====================

function Connect-AuditGraph {
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication module not found. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }

    $scopes = @('Application.Read.All', 'Directory.Read.All', 'RoleManagement.Read.Directory')
    if ($IncludeSignInActivity) { $scopes += 'AuditLog.Read.All' }

    switch ($script:ParamSetName) {
        'AppOnly' {
            Write-Step "Connecting to Microsoft Graph (app-only, certificate)"
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
        }
        'ManagedIdentity' {
            Write-Step "Connecting to Microsoft Graph (managed identity)"
            Connect-MgGraph -Identity -NoWelcome
        }
        default {
            $ctx = Get-MgContext
            $missing = if ($ctx) { $scopes | Where-Object { $_ -notin $ctx.Scopes } } else { $scopes }
            if (-not $ctx -or $missing) {
                Write-Step "Connecting to Microsoft Graph (delegated). Scopes: $($scopes -join ', ')"
                $p = @{ Scopes = $scopes; NoWelcome = $true }
                if ($TenantId) { $p.TenantId = $TenantId }
                Connect-MgGraph @p
            }
            else { Write-Step "Reusing existing Graph session ($($ctx.Account))" }
        }
    }
}

#endregion

#region ===================== Data collection =====================

function Get-AuditData {
    $data = [ordered]@{}

    Write-Step 'Reading tenant information'
    $org = (Invoke-GraphPaged -Uri 'v1.0/organization?$select=id,displayName,verifiedDomains')[0]
    $data.Tenant = [ordered]@{
        Id          = $org.id
        DisplayName = $org.displayName
        Domain      = (@($org.verifiedDomains) | Where-Object { $_.isDefault } | Select-Object -First 1).name
    }

    Write-Step 'Reading application objects (App Registrations)'
    $appSelect = 'id,appId,displayName,createdDateTime,signInAudience,publisherDomain,verifiedPublisher,' +
                 'passwordCredentials,keyCredentials,requiredResourceAccess,web,spa,isFallbackPublicClient'
    $data.Applications = Invoke-GraphPaged -Uri "v1.0/applications?`$select=$appSelect&`$top=999"
    Write-Host "    $($data.Applications.Count) application objects"

    Write-Step 'Reading service principals (Enterprise Apps, Managed Identities, third-party)'
    $spSelect = 'id,appId,displayName,servicePrincipalType,appOwnerOrganizationId,accountEnabled,createdDateTime,' +
                'passwordCredentials,keyCredentials,verifiedPublisher,publisherName,appRoles,oauth2PermissionScopes,' +
                'preferredSingleSignOnMode,signInAudience,tags'
    $data.ServicePrincipals = Invoke-GraphPaged -Uri "v1.0/servicePrincipals?`$select=$spSelect&`$top=999"
    Write-Host "    $($data.ServicePrincipals.Count) service principals"

    Write-Step 'Reading delegated permission grants (oauth2PermissionGrants)'
    $data.DelegatedGrants = Invoke-GraphPaged -Uri 'v1.0/oauth2PermissionGrants?$top=999'
    Write-Host "    $($data.DelegatedGrants.Count) grants"

    Write-Step 'Reading directory role definitions and assignments'
    $data.RoleDefinitions = Invoke-GraphPaged -Uri 'v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,templateId'
    $data.RoleAssignments = Invoke-GraphPaged -Uri 'v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId'

    # Scope reduction: which SPs are in scope for per-object calls
    $inScopeSp = @($data.ServicePrincipals | Where-Object {
        $IncludeMicrosoftApps -or (Get-Prop $_ 'servicePrincipalType') -eq 'ManagedIdentity' -or
        ((Get-Prop $_ 'appOwnerOrganizationId') -notin $script:MicrosoftTenantIds)
    })

    Write-Step "Reading granted application permissions for $($inScopeSp.Count) service principals"
    $req = @{}
    foreach ($sp in $inScopeSp) { $req["ara_$($sp.id)"] = "/servicePrincipals/$($sp.id)/appRoleAssignments?`$top=999" }
    $data.AppRoleAssignments = Invoke-GraphBatch -Requests $req -Activity 'Application permissions'

    Write-Step 'Reading owners of service principals and applications'
    $req = @{}
    foreach ($sp in $inScopeSp)            { $req["spo_$($sp.id)"]  = "/servicePrincipals/$($sp.id)/owners?`$select=id,displayName,userPrincipalName" }
    foreach ($app in $data.Applications)   { $req["appo_$($app.id)"] = "/applications/$($app.id)/owners?`$select=id,displayName,userPrincipalName" }
    $data.Owners = Invoke-GraphBatch -Requests $req -Activity 'Owners'

    Write-Step 'Reading federated identity credentials'
    $req = @{}
    foreach ($app in $data.Applications) { $req["fic_$($app.id)"] = "/applications/$($app.id)/federatedIdentityCredentials" }
    $data.FederatedCredentials = Invoke-GraphBatch -Requests $req -Activity 'Federated credentials'

    $data.SignInActivity = @{}
    if ($IncludeSignInActivity) {
        Write-Step 'Reading service principal sign-in activity (beta, P1/P2)'
        try {
            foreach ($a in (Invoke-GraphPaged -Uri 'beta/reports/servicePrincipalSignInActivities?$top=999')) {
                $last = Get-Prop (Get-Prop $a 'lastSignInActivity') 'lastSignInDateTime'
                $data.SignInActivity[[string]$a.appId] = ConvertTo-UtcDate $last
            }
            Write-Host "    $($data.SignInActivity.Count) activity records"
        }
        catch {
            Write-Warning "Sign-in activity unavailable (licence or permission missing): $($_.Exception.Message)"
            $script:SignInActivityFailed = $true
        }
    }

    return $data
}

#endregion

#region ===================== Analysis =====================

function Get-CredentialStatus {
    param([Nullable[datetime]]$End, [datetime]$Now)
    if (-not $End) { return @{ Status = 'No expiry'; DaysLeft = $null } }
    $days = [int][Math]::Floor(($End - $Now).TotalDays)
    $status = if ($End.Year -ge 2299) { 'No expiry' }
              elseif ($days -lt 0)                    { 'Expired' }
              elseif ($days -le $ExpiryCriticalDays)  { "< $ExpiryCriticalDays days" }
              elseif ($days -le $ExpiryWarningDays)   { "< $ExpiryWarningDays days" }
              elseif ($days -le $ExpiryNoticeDays)    { "< $ExpiryNoticeDays days" }
              else                                    { 'Valid' }
    if ($status -eq 'No expiry') { $days = $null }
    return @{ Status = $status; DaysLeft = $days }
}

function Get-LevelFromScore {
    param([int]$Score)
    foreach ($k in $script:LevelThresholds.Keys) { if ($Score -ge $script:LevelThresholds[$k]) { return $k } }
    return 'Secure'
}

function Invoke-AuditAnalysis {
    param([Parameter(Mandatory)]$Data)

    $now = (Get-Date).ToUniversalTime()

    # ---- Lookup tables ----
    $spById    = @{}; $spByAppId = @{}
    foreach ($sp in $Data.ServicePrincipals) { $spById[$sp.id] = $sp; $spByAppId[$sp.appId] = $sp }
    $appByAppId = @{}
    foreach ($a in $Data.Applications) { $appByAppId[$a.appId] = $a }

    $roleDefName = @{}
    foreach ($rd in $Data.RoleDefinitions) { $roleDefName[$rd.id] = $rd.displayName; if ($rd.templateId) { $roleDefName[$rd.templateId] = $rd.displayName } }

    $rolesByPrincipal = @{}
    foreach ($ra in $Data.RoleAssignments) {
        if (-not $rolesByPrincipal.ContainsKey($ra.principalId)) { $rolesByPrincipal[$ra.principalId] = [System.Collections.Generic.List[object]]::new() }
        $rolesByPrincipal[$ra.principalId].Add($ra)
    }

    $grantsByClient = @{}
    foreach ($g in $Data.DelegatedGrants) {
        if (-not $grantsByClient.ContainsKey($g.clientId)) { $grantsByClient[$g.clientId] = [System.Collections.Generic.List[object]]::new() }
        $grantsByClient[$g.clientId].Add($g)
    }

    # Resolve appRole / scope IDs per resource SP
    $resolveRole = {
        param($resourceSp, $roleId)
        if (-not $resourceSp) { return $roleId }
        $r = @(Get-Prop $resourceSp 'appRoles' @()) | Where-Object { $_.id -eq $roleId } | Select-Object -First 1
        if ($r) { return $r.value }
        if ($roleId -eq '00000000-0000-0000-0000-000000000000') { return '(default access)' }
        return $roleId
    }
    $resolveScope = {
        param($resourceSp, $scopeId)
        if (-not $resourceSp) { return $scopeId }
        $s = @(Get-Prop $resourceSp 'oauth2PermissionScopes' @()) | Where-Object { $_.id -eq $scopeId } | Select-Object -First 1
        if ($s) { return $s.value } else { return $scopeId }
    }

    # ---- Build the inventory keyed by appId (union of applications and SPs) ----
    $allAppIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($a in $Data.Applications)      { [void]$allAppIds.Add($a.appId) }
    foreach ($s in $Data.ServicePrincipals) { [void]$allAppIds.Add($s.appId) }

    $results = [System.Collections.Generic.List[object]]::new()
    $tenantId = $Data.Tenant.Id

    foreach ($appId in $allAppIds) {
        $app = $appByAppId[$appId]
        $sp  = $spByAppId[$appId]

        $ownerOrg   = Get-Prop $sp 'appOwnerOrganizationId'
        $spType     = Get-Prop $sp 'servicePrincipalType' ''
        $isMicrosoft = ($ownerOrg -in $script:MicrosoftTenantIds) -and ($spType -ne 'ManagedIdentity')
        if ($isMicrosoft -and -not $IncludeMicrosoftApps) { continue }

        $category = if ($spType -eq 'ManagedIdentity') { 'Managed Identity' }
                    elseif ($isMicrosoft) { 'Microsoft first-party' }
                    elseif ($app) { if ($sp) { 'Registered in tenant' } else { 'Registration only (no SP)' } }
                    elseif ($ownerOrg -and $ownerOrg -ne $tenantId) { 'Third-party (multi-tenant)' }
                    else { 'Enterprise App' }

        $findings = [System.Collections.Generic.List[object]]::new()
        $addFinding = {
            param([double]$Points, [string]$Area, [string]$Detail, [string]$Severity = 'info')
            $findings.Add([pscustomobject]@{ Points = [Math]::Round($Points, 1); Area = $Area; Detail = $Detail; Severity = $Severity })
        }
        $floor = 'Secure'
        $raiseFloor = { param([string]$lvl) if ($script:LevelRank[$lvl] -gt $script:LevelRank[$floor]) { Set-Variable -Name floor -Value $lvl -Scope 1 } }

        # ---------- Application permissions (granted) ----------
        $appPerms = [System.Collections.Generic.List[object]]::new()
        if ($sp) {
            $assign = $Data.AppRoleAssignments["ara_$($sp.id)"]
            foreach ($as in @($assign)) {
                if (-not $as) { continue }
                $resSp = $spById[$as.resourceId]
                $value = & $resolveRole $resSp $as.appRoleId
                $cat   = $script:PermissionCatalog[$value]
                $tier  = if ($cat) { $cat.Tier } else { 'Unclassified' }
                $appPerms.Add([pscustomobject]@{
                    Permission = $value
                    Resource   = $as.resourceDisplayName
                    Type       = 'Application'
                    Tier       = $tier
                    Reason     = if ($cat) { $cat.Reason } else { '' }
                    GrantedOn  = ConvertTo-UtcDate (Get-Prop $as 'createdDateTime')
                })
                if ($cat) {
                    & $addFinding $cat.Weight 'Application permission' "$value ($($as.resourceDisplayName)): $($cat.Reason)" $cat.Tier.ToLower()
                    if ($cat.Tier -eq 'Critical') { & $raiseFloor 'Critical' }
                    elseif ($cat.Tier -eq 'High') { & $raiseFloor 'High' }
                }
            }
            # Unclassified app permissions still carry some weight (unknown write access)
            $unclassifiedWrite = @($appPerms | Where-Object { $_.Tier -eq 'Unclassified' -and $_.Permission -match 'Write|Manage|FullControl|Send' })
            if ($unclassifiedWrite.Count) {
                & $addFinding ([Math]::Min(15, 5 * $unclassifiedWrite.Count)) 'Application permission' "Unclassified write permissions: $((@($unclassifiedWrite | ForEach-Object Permission)) -join ', ')" 'medium'
            }
        }

        # ---------- Delegated permissions (granted) ----------
        $delegated = [System.Collections.Generic.List[object]]::new()
        if ($sp -and $grantsByClient.ContainsKey($sp.id)) {
            $grantGroups = $grantsByClient[$sp.id] | Group-Object -Property resourceId, consentType
            foreach ($gg in $grantGroups) {
                $first   = $gg.Group[0]
                $resSp   = $spById[$first.resourceId]
                $resName = if ($resSp) { $resSp.displayName } else { $first.resourceId }
                $scopes  = @($gg.Group | ForEach-Object { "$($_.scope)".Trim() -split '\s+' } | Where-Object { $_ } | Sort-Object -Unique)
                $isAll   = $first.consentType -eq 'AllPrincipals'
                $userCnt = if ($isAll) { $null } else { @($gg.Group.principalId | Sort-Object -Unique).Count }
                $mult    = if ($isAll) { 0.5 } else { 0.3 }
                foreach ($s in $scopes) {
                    $cat  = $script:PermissionCatalog[$s]
                    $delegated.Add([pscustomobject]@{
                        Permission = $s
                        Resource   = $resName
                        Type       = 'Delegated'
                        Consent    = if ($isAll) { 'Admin (all users)' } else { "User consent ($userCnt user(s))" }
                        Tier       = if ($cat) { $cat.Tier } else { 'Unclassified' }
                        Reason     = if ($cat) { $cat.Reason } else { '' }
                    })
                    if ($cat) {
                        $consentTxt = if ($isAll) { 'all users' } else { "$userCnt user(s)" }
                        & $addFinding ($cat.Weight * $mult) 'Delegated permission' "$s ($resName, consented for $consentTxt): $($cat.Reason)" $cat.Tier.ToLower()
                        if ($isAll -and $cat.Tier -eq 'Critical') { & $raiseFloor 'High' }
                    }
                }
            }
        }

        # ---------- Directory roles ----------
        $roles = [System.Collections.Generic.List[object]]::new()
        if ($sp -and $rolesByPrincipal.ContainsKey($sp.id)) {
            foreach ($ra in $rolesByPrincipal[$sp.id]) {
                $rn = $roleDefName[$ra.roleDefinitionId]; if (-not $rn) { $rn = $ra.roleDefinitionId }
                $w  = if ($script:RoleCatalog.ContainsKey($rn)) { $script:RoleCatalog[$rn] } else { $script:DefaultRoleWeight }
                $roles.Add([pscustomobject]@{ Role = $rn; Scope = $ra.directoryScopeId })
                $sev = if ($w -ge 45) { 'critical' } elseif ($w -ge 30) { 'high' } else { 'medium' }
                & $addFinding $w 'Directory role' "Entra ID role '$rn' assigned to the service principal (scope $($ra.directoryScopeId))" $sev
                if ($w -ge 45) { & $raiseFloor 'Critical' } elseif ($w -ge 30) { & $raiseFloor 'High' }
            }
        }

        # ---------- Requested but not consented ----------
        $requestedOnly = [System.Collections.Generic.List[object]]::new()
        if ($app) {
            $grantedNames = @($appPerms | ForEach-Object Permission) + @($delegated | ForEach-Object Permission)
            foreach ($rra in @(Get-Prop $app 'requiredResourceAccess' @())) {
                $resSp = $spByAppId[$rra.resourceAppId]
                foreach ($ra in @($rra.resourceAccess)) {
                    $name = if ($ra.type -eq 'Role') { & $resolveRole $resSp $ra.id } else { & $resolveScope $resSp $ra.id }
                    if ($name -notin $grantedNames) {
                        $requestedOnly.Add([pscustomobject]@{
                            Permission = $name
                            Resource   = if ($resSp) { $resSp.displayName } else { $rra.resourceAppId }
                            Type       = if ($ra.type -eq 'Role') { 'Application' } else { 'Delegated' }
                        })
                    }
                }
            }
        }

        # ---------- Credentials ----------
        $creds = [System.Collections.Generic.List[object]]::new()
        $samlKeyIds = @()
        if ($sp) {
            $samlKeyIds = @(@(Get-Prop $sp 'keyCredentials' @()) | Where-Object { $_.usage -eq 'Sign' } | ForEach-Object { Get-Prop $_ 'customKeyIdentifier' } | Where-Object { $_ })
        }
        $addCred = {
            param($c, [string]$Source, [string]$Kind)
            $start = ConvertTo-UtcDate (Get-Prop $c 'startDateTime')
            $end   = ConvertTo-UtcDate (Get-Prop $c 'endDateTime')
            $st    = Get-CredentialStatus -End $end -Now $now
            $life  = if ($start -and $end -and $end.Year -lt 2299) { [int]($end - $start).TotalDays } else { $null }
            $hint  = Get-Prop $c 'hint' ''
            $name  = Get-Prop $c 'displayName' ''
            $creds.Add([pscustomobject]@{
                Type         = $Kind
                Source       = $Source
                Name         = if ($name) { $name } elseif ($hint) { "hint: $hint***" } else { '(unnamed)' }
                KeyId        = Get-Prop $c 'keyId' ''
                Start        = $start
                End          = $end
                DaysLeft     = $st.DaysLeft
                LifetimeDays = $life
                Status       = $st.Status
            })
        }
        if ($app) {
            foreach ($c in @(Get-Prop $app 'passwordCredentials' @())) { & $addCred $c 'Application' 'Secret' }
            foreach ($c in @(Get-Prop $app 'keyCredentials' @()))      { & $addCred $c 'Application' 'Certificate' }
        }
        if ($sp) {
            foreach ($c in @(Get-Prop $sp 'keyCredentials' @())) {
                $kind = if ($c.usage -eq 'Sign' -or (Get-Prop $sp 'preferredSingleSignOnMode') -eq 'saml') { 'SAML signing certificate' } else { 'Certificate' }
                & $addCred $c 'Service principal' $kind
            }
            foreach ($c in @(Get-Prop $sp 'passwordCredentials' @())) {
                $cki  = Get-Prop $c 'customKeyIdentifier'
                $kind = if (($cki -and $cki -in $samlKeyIds) -or (Get-Prop $sp 'preferredSingleSignOnMode') -eq 'saml') { 'SAML signing key' } else { 'Secret' }
                & $addCred $c 'Service principal' $kind
            }
        }
        $fics = @()
        if ($app) { $fics = @($Data.FederatedCredentials["fic_$($app.id)"]) | Where-Object { $_ } }
        foreach ($f in $fics) {
            $creds.Add([pscustomobject]@{
                Type = 'Federated'; Source = 'Application'; Name = "$($f.name) | issuer: $($f.issuer) | subject: $($f.subject)"
                KeyId = $f.id; Start = $null; End = $null; DaysLeft = $null; LifetimeDays = $null; Status = 'No secret (federated)'
            })
        }

        $authCreds = @($creds | Where-Object { $_.Type -in 'Secret', 'Certificate', 'Federated' })
        $authModes = [System.Collections.Generic.List[string]]::new()
        if ($spType -eq 'ManagedIdentity') { $authModes.Add('Managed Identity') }
        foreach ($t in 'Secret', 'Certificate', 'Federated') { if ($authCreds | Where-Object Type -eq $t) { $authModes.Add($t) } }
        if (-not $authModes.Count) {
            $authModes.Add($(if ($category -eq 'Third-party (multi-tenant)') { 'Vendor managed' } else { 'None' }))
        }

        # Credential hygiene findings
        $activeSecrets = @($creds | Where-Object { $_.Type -eq 'Secret' -and $_.Status -ne 'Expired' })
        $hasPerms = ($appPerms.Count + $delegated.Count + $roles.Count) -gt 0
        if ($activeSecrets.Count) {
            & $addFinding 8 'Credential' "Authenticates with $($activeSecrets.Count) client secret(s): prefer certificate, federated credential or managed identity" 'medium'
        }
        if ($activeSecrets.Count -gt 1) {
            & $addFinding 5 'Credential' "$($activeSecrets.Count) active secrets at the same time (unclear ownership, larger exposure)" 'medium'
        }
        foreach ($s in $activeSecrets) {
            if ($s.Status -eq 'No expiry' -or ($s.LifetimeDays -and $s.LifetimeDays -gt 730)) {
                & $addFinding 15 'Credential' "Secret '$($s.Name)' has an excessive lifetime ($(if ($s.LifetimeDays) { "$($s.LifetimeDays) days" } else { 'no expiry' }))" 'high'
            }
            elseif ($s.LifetimeDays -and $s.LifetimeDays -gt 365) {
                & $addFinding 8 'Credential' "Secret '$($s.Name)' lifetime above 12 months ($($s.LifetimeDays) days)" 'medium'
            }
        }
        $spSecrets = @($activeSecrets | Where-Object { $_.Source -eq 'Service principal' })
        if ($spSecrets.Count) {
            & $addFinding 20 'Credential' "Secret added directly on the service principal (invisible in App Registrations, common persistence technique)" 'high'
            & $raiseFloor 'Medium'
        }
        $expired = @($creds | Where-Object { $_.Status -eq 'Expired' -and $_.Type -in 'Secret', 'Certificate' })
        if ($expired.Count) {
            & $addFinding 3 'Credential' "$($expired.Count) expired credential(s) never removed" 'low'
        }

        # ---------- Governance ----------
        $owners = @()
        if ($app) { $owners += @($Data.Owners["appo_$($app.id)"]) | Where-Object { $_ } }
        if ($sp)  { $owners += @($Data.Owners["spo_$($sp.id)"])   | Where-Object { $_ } }
        $owners = @($owners | Sort-Object -Property id -Unique)
        $ownerNames = @($owners | ForEach-Object { $u = Get-Prop $_ 'userPrincipalName'; if ($u) { $u } else { Get-Prop $_ 'displayName' $_.id } })
        if ($category -in 'Registered in tenant', 'Registration only (no SP)', 'Enterprise App' -and $owners.Count -eq 0 -and ($hasPerms -or $authCreds.Count)) {
            & $addFinding 8 'Governance' 'No owner assigned: nobody accountable for this application' 'medium'
        }
        $guestOwners = @($ownerNames | Where-Object { $_ -match '#EXT#' })
        if ($guestOwners.Count) {
            & $addFinding 10 'Governance' "Guest account(s) owning the application: $($guestOwners -join ', ')" 'high'
        }

        $verifiedPub = Get-Prop (Get-Prop $(if ($sp) { $sp } else { $app }) 'verifiedPublisher') 'displayName'
        if ($category -eq 'Third-party (multi-tenant)' -and -not $verifiedPub -and $hasPerms) {
            & $addFinding 10 'Governance' 'Third-party application from an unverified publisher' 'medium'
        }
        $audience = Get-Prop $app 'signInAudience' (Get-Prop $sp 'signInAudience' '')
        if ($app -and $audience -in 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount' -and $appPerms.Count) {
            & $addFinding 5 'Governance' "Registered as multi-tenant ($audience) while holding application permissions" 'low'
        }

        # ---------- Configuration ----------
        if ($app) {
            $web = Get-Prop $app 'web'
            $igs = Get-Prop $web 'implicitGrantSettings'
            if ((Get-Prop $igs 'enableAccessTokenIssuance' $false) -eq $true) {
                & $addFinding 5 'Configuration' 'Implicit grant flow enabled for access tokens (deprecated, prefer auth code + PKCE)' 'low'
            }
            $uris = @(@(Get-Prop $web 'redirectUris' @()) + @(Get-Prop (Get-Prop $app 'spa') 'redirectUris' @())) | Where-Object { $_ }
            $httpUris = @($uris | Where-Object { $_ -match '^http://' -and $_ -notmatch '^http://(localhost|127\.0\.0\.1)' })
            $wildUris = @($uris | Where-Object { $_ -match '\*' })
            if ($httpUris.Count) { & $addFinding 5 'Configuration' "Non-HTTPS redirect URI(s): $($httpUris -join ', ')" 'low' }
            if ($wildUris.Count) { & $addFinding 8 'Configuration' "Wildcard redirect URI(s): $($wildUris -join ', ')" 'medium' }
        }

        # ---------- Activity ----------
        $lastSignIn = $null
        if ($IncludeSignInActivity -and -not $script:SignInActivityFailed) {
            $lastSignIn = $Data.SignInActivity[$appId]
            $inactive = (-not $lastSignIn) -or (($now - $lastSignIn).TotalDays -gt $InactiveDays)
            if ($inactive -and $hasPerms) {
                $permScore = 0.0
                foreach ($f in $findings) { if ($f.Area -in 'Application permission', 'Directory role') { $permScore += $f.Points } }
                $pts = if ($permScore -ge 40) { 15 } else { 8 }
                $txt = if ($lastSignIn) { "Last sign-in $([int]($now - $lastSignIn).TotalDays) days ago" } else { "No sign-in recorded" }
                & $addFinding $pts 'Activity' "$txt while holding permissions: candidate for removal" 'medium'
            }
        }

        # ---------- Score ----------
        $raw = 0.0
        foreach ($f in $findings) { $raw += $f.Points }
        $enabled = [bool](Get-Prop $sp 'accountEnabled' $true)
        if ($sp -and -not $enabled) {
            & $addFinding (-[Math]::Round($raw * 0.7, 1)) 'Mitigation' 'Service principal disabled: sign-in blocked (score reduced by 70%)' 'info'
            $raw = $raw * 0.3
            $floor = 'Secure'
        }
        $score = [int][Math]::Min(100, [Math]::Round($raw))
        $level = Get-LevelFromScore -Score $score
        # Hygiene, governance and configuration factors alone cannot make an app Critical:
        # Critical requires a Critical-tier capability or at least 40 points of real permissions.
        if ($level -eq 'Critical' -and $floor -ne 'Critical') {
            $permPoints = 0.0
            foreach ($f in $findings) { if ($f.Area -in 'Application permission', 'Delegated permission', 'Directory role') { $permPoints += $f.Points } }
            if ($permPoints -lt 40) { $level = 'High' }
        }
        if ($script:LevelRank[$floor] -gt $script:LevelRank[$level]) { $level = $floor }

        # Next credential expiry (auth or SAML, not expired)
        $nextExp = $creds | Where-Object { $null -ne $_.DaysLeft -and $_.DaysLeft -ge 0 } | Sort-Object DaysLeft | Select-Object -First 1

        $results.Add([pscustomobject]@{
            DisplayName       = if ($app) { $app.displayName } else { $sp.displayName }
            AppId             = $appId
            ApplicationId     = Get-Prop $app 'id'
            ServicePrincipalId= Get-Prop $sp 'id'
            Category          = $category
            Publisher         = if ($verifiedPub) { "$verifiedPub (verified)" } else { Get-Prop $sp 'publisherName' (Get-Prop $app 'publisherDomain' '') }
            SignInAudience    = $audience
            Enabled           = $enabled
            Created           = ConvertTo-UtcDate (Get-Prop $app 'createdDateTime' (Get-Prop $sp 'createdDateTime'))
            AuthModes         = @($authModes)
            Owners            = @($ownerNames)
            LastSignIn        = $lastSignIn
            Score             = $score
            Level             = $level
            ApplicationPermissions = @($appPerms)
            DelegatedPermissions   = @($delegated)
            DirectoryRoles         = @($roles)
            RequestedNotGranted    = @($requestedOnly)
            Credentials            = @($creds)
            NextExpiryDays         = if ($nextExp) { $nextExp.DaysLeft } else { $null }
            Findings               = @($findings | Sort-Object Points -Descending)
        })
    }

    return , ($results | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, DisplayName)
}

#endregion

#region ===================== Report =====================

function New-HtmlReport {
    param($Results, $Tenant, [string]$Path)

    $now = (Get-Date).ToUniversalTime()
    $toIso = { param($d) if ($d) { ([datetime]$d).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") } else { $null } }

    # Flatten to a JSON-friendly structure for the client-side renderer
    $payload = [ordered]@{
        tenant    = $Tenant
        generated = & $toIso $now
        options   = [ordered]@{
            includeMicrosoft = [bool]$IncludeMicrosoftApps
            signInActivity   = [bool]($IncludeSignInActivity -and -not $script:SignInActivityFailed)
            inactiveDays     = $InactiveDays
            expiry           = @($ExpiryCriticalDays, $ExpiryWarningDays, $ExpiryNoticeDays)
        }
        apps = @($Results | ForEach-Object {
            $r = $_
            [ordered]@{
                name = $r.DisplayName; appId = $r.AppId; appObjId = $r.ApplicationId; spId = $r.ServicePrincipalId
                category = $r.Category; publisher = $r.Publisher; audience = $r.SignInAudience; enabled = $r.Enabled
                created = & $toIso $r.Created; lastSignIn = & $toIso $r.LastSignIn
                auth = @($r.AuthModes); owners = @($r.Owners); score = $r.Score; level = $r.Level
                nextExpiry = $r.NextExpiryDays
                appPerms = @($r.ApplicationPermissions | ForEach-Object { [ordered]@{ p = $_.Permission; r = $_.Resource; t = $_.Tier; why = $_.Reason } })
                delPerms = @($r.DelegatedPermissions   | ForEach-Object { [ordered]@{ p = $_.Permission; r = $_.Resource; t = $_.Tier; c = $_.Consent; why = $_.Reason } })
                roles    = @($r.DirectoryRoles         | ForEach-Object { [ordered]@{ n = $_.Role; s = $_.Scope } })
                requested= @($r.RequestedNotGranted    | ForEach-Object { [ordered]@{ p = $_.Permission; r = $_.Resource; ty = $_.Type } })
                creds    = @($r.Credentials | ForEach-Object { [ordered]@{
                                ty = $_.Type; src = $_.Source; n = $_.Name; st = $_.Status; d = $_.DaysLeft; life = $_.LifetimeDays
                                start = & $toIso $_.Start; end = & $toIso $_.End } })
                findings = @($r.Findings | ForEach-Object { [ordered]@{ pts = $_.Points; a = $_.Area; d = $_.Detail; s = $_.Severity } })
            }
        })
    }
    $json = ($payload | ConvertTo-Json -Depth 10 -Compress) -replace '</', '<\/'

    $html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Entra ID Application Risk Audit</title>
<style>
:root{
  --bg:#f5f7fa;--card:#fff;--text:#1f2937;--muted:#6b7280;--border:#e5e7eb;--accent:#0f4c81;
  --critical:#991b1b;--critical-bg:#fee2e2;--high:#c2410c;--high-bg:#ffedd5;--medium:#b45309;--medium-bg:#fef3c7;
  --low:#1d4ed8;--low-bg:#dbeafe;--secure:#15803d;--secure-bg:#dcfce7;
}
*{box-sizing:border-box}
body{margin:0;font-family:"Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif;background:var(--bg);color:var(--text);font-size:14px}
header{background:linear-gradient(120deg,#0b2545,#0f4c81);color:#fff;padding:24px 32px}
header h1{margin:0 0 4px;font-size:22px;font-weight:600}
header .meta{opacity:.85;font-size:13px}
main{padding:24px 32px;max-width:1600px;margin:0 auto}
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin-bottom:20px}
.kpi{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:14px 16px;border-top:4px solid var(--accent);cursor:default}
.kpi.clickable{cursor:pointer}.kpi.clickable:hover{box-shadow:0 2px 8px rgba(0,0,0,.08)}
.kpi .v{font-size:26px;font-weight:700}.kpi .l{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.03em}
.kpi.critical{border-top-color:var(--critical)}.kpi.critical .v{color:var(--critical)}
.kpi.high{border-top-color:var(--high)}.kpi.high .v{color:var(--high)}
.kpi.medium{border-top-color:var(--medium)}.kpi.medium .v{color:var(--medium)}
.kpi.low{border-top-color:var(--low)}.kpi.low .v{color:var(--low)}
.kpi.secure{border-top-color:var(--secure)}.kpi.secure .v{color:var(--secure)}
.kpi.warn{border-top-color:#7c3aed}.kpi.warn .v{color:#7c3aed}
.legend{display:flex;flex-wrap:wrap;gap:16px;background:var(--card);border:1px solid var(--border);border-radius:10px;padding:12px 16px;margin-bottom:20px;font-size:13px}
.legend div{display:flex;align-items:center;gap:8px}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap}
.b-critical{background:var(--critical);color:#fff}.b-high{background:var(--high);color:#fff}.b-medium{background:var(--medium);color:#fff}
.b-low{background:var(--low);color:#fff}.b-secure{background:var(--secure);color:#fff}
.t-critical{background:var(--critical-bg);color:var(--critical)}.t-high{background:var(--high-bg);color:var(--high)}
.t-medium{background:var(--medium-bg);color:var(--medium)}.t-low{background:var(--low-bg);color:var(--low)}
.t-unclassified,.t-info{background:#f3f4f6;color:#4b5563}
.tabs{display:flex;gap:4px;border-bottom:2px solid var(--border);margin-bottom:16px}
.tab{padding:10px 18px;cursor:pointer;border:none;background:none;font-size:14px;font-weight:600;color:var(--muted);border-bottom:3px solid transparent;margin-bottom:-2px}
.tab.active{color:var(--accent);border-bottom-color:var(--accent)}
.toolbar{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:12px;align-items:center}
.toolbar input,.toolbar select{padding:8px 10px;border:1px solid var(--border);border-radius:6px;font-size:13px;background:#fff}
.toolbar input{min-width:280px}
.toolbar .count{color:var(--muted);margin-left:auto;font-size:13px}
.toolbar button{padding:8px 12px;border:1px solid var(--border);border-radius:6px;background:#fff;cursor:pointer;font-size:13px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--border);border-radius:10px;overflow:hidden}
th{background:#f9fafb;text-align:left;padding:10px 12px;font-size:12px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted);border-bottom:1px solid var(--border);cursor:pointer;user-select:none;white-space:nowrap}
th.sorted-asc::after{content:" \25B2"}th.sorted-desc::after{content:" \25BC"}
td{padding:10px 12px;border-bottom:1px solid var(--border);vertical-align:top}
tr.row{cursor:pointer}tr.row:hover td{background:#f9fafb}
tr.row td:first-child{border-left:5px solid transparent}
tr.lv-Critical td:first-child{border-left-color:var(--critical)}tr.lv-High td:first-child{border-left-color:var(--high)}
tr.lv-Medium td:first-child{border-left-color:var(--medium)}tr.lv-Low td:first-child{border-left-color:var(--low)}
tr.lv-Secure td:first-child{border-left-color:var(--secure)}
.score{font-weight:700;font-size:15px}
.bar{height:6px;background:#e5e7eb;border-radius:3px;margin-top:4px;width:70px}.bar span{display:block;height:6px;border-radius:3px}
.name{font-weight:600}.sub{color:var(--muted);font-size:12px;font-family:Consolas,monospace}
.chip{display:inline-block;padding:1px 8px;margin:1px 2px 1px 0;border-radius:4px;font-size:12px;background:#eef2ff;color:#3730a3}
.chip.secret{background:#fef3c7;color:#92400e}.chip.cert{background:#dcfce7;color:#166534}.chip.fed{background:#e0f2fe;color:#075985}
.chip.mi{background:#ede9fe;color:#5b21b6}.chip.none{background:#f3f4f6;color:#4b5563}
tr.detail td{background:#fbfcfe;padding:16px 20px}
.dgrid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
@media(max-width:1100px){.dgrid{grid-template-columns:1fr}}
.panel{background:#fff;border:1px solid var(--border);border-radius:8px;padding:12px 14px}
.panel h4{margin:0 0 8px;font-size:13px;text-transform:uppercase;color:var(--accent);letter-spacing:.03em}
.panel table{border:none;font-size:13px}.panel th{cursor:default;font-size:11px;padding:6px 8px}.panel td{padding:6px 8px}
.pts{font-weight:700;text-align:right;white-space:nowrap}
.pts.neg{color:var(--secure)}
.empty{color:var(--muted);font-style:italic}
.st-Expired{color:#fff;background:#7f1d1d}.st-crit{background:var(--critical-bg);color:var(--critical)}
.st-warn{background:var(--high-bg);color:var(--high)}.st-notice{background:var(--medium-bg);color:var(--medium)}
.st-ok{background:var(--secure-bg);color:var(--secure)}.st-noexp{background:#fae8ff;color:#86198f}
.ids{font-family:Consolas,monospace;font-size:12px;color:var(--muted);line-height:1.7}
footer{text-align:center;color:var(--muted);font-size:12px;padding:24px}
.hidden{display:none}
@media print{.toolbar,.tabs{display:none}tr.detail{display:none}}
</style>
</head>
<body>
<header>
  <h1>Entra ID Application Risk Audit</h1>
  <div class="meta" id="meta"></div>
</header>
<main>
  <section class="kpis" id="kpis"></section>
  <section class="legend">
    <div><span class="badge b-critical">Critical</span> 70-100 or tenant takeover capability</div>
    <div><span class="badge b-high">High</span> 45-69 or mass data access</div>
    <div><span class="badge b-medium">Medium</span> 25-44</div>
    <div><span class="badge b-low">Low</span> 10-24</div>
    <div><span class="badge b-secure">Secure</span> 0-9</div>
  </section>

  <nav class="tabs">
    <button class="tab active" data-tab="apps">Applications</button>
    <button class="tab" data-tab="creds">Credentials expiry</button>
    <button class="tab" data-tab="method">Scoring method</button>
  </nav>

  <section id="tab-apps">
    <div class="toolbar">
      <input id="q" type="search" placeholder="Search name, App ID, permission, owner...">
      <select id="fLevel"><option value="">All levels</option><option>Critical</option><option>High</option><option>Medium</option><option>Low</option><option>Secure</option></select>
      <select id="fAuth"><option value="">All auth modes</option><option>Secret</option><option>Certificate</option><option>Federated</option><option>Managed Identity</option><option>Vendor managed</option><option>None</option></select>
      <select id="fCat"><option value="">All categories</option></select>
      <button id="expandAll">Expand all</button>
      <span class="count" id="count"></span>
    </div>
    <table id="appTable">
      <thead><tr>
        <th data-k="level">Level</th><th data-k="score">Score</th><th data-k="name">Application</th><th data-k="category">Category</th>
        <th data-k="auth">Auth mode</th><th data-k="appPerms">App perms</th><th data-k="delPerms">Delegated</th><th data-k="roles">Roles</th>
        <th data-k="owners">Owners</th><th data-k="lastSignIn">Last sign-in</th><th data-k="nextExpiry">Next expiry</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </section>

  <section id="tab-creds" class="hidden">
    <div class="toolbar">
      <select id="fStatus"><option value="">All statuses</option></select>
      <select id="fType"><option value="">All types</option></select>
      <span class="count" id="ccount"></span>
    </div>
    <table id="credTable">
      <thead><tr><th>Status</th><th>Days left</th><th>Application</th><th>Type</th><th>Stored on</th><th>Name / hint</th><th>Expires (UTC)</th><th>Lifetime</th><th>App level</th></tr></thead>
      <tbody></tbody>
    </table>
  </section>

  <section id="tab-method" class="hidden">
    <div class="panel" style="max-width:1000px">
      <h4>How the score is computed</h4>
      <p>Each application starts at 0. Points are added for every risk factor found, then capped at 100. The detail panel of each application lists every factor with its points.</p>
      <table>
        <tr><th>Factor</th><th>Points</th></tr>
        <tr><td>Application permission, Critical tier (e.g. RoleManagement.ReadWrite.Directory, Application.ReadWrite.All, full_access_as_app, DeviceManagementConfiguration.ReadWrite.All)</td><td>40 to 60, forces level Critical</td></tr>
        <tr><td>Application permission, High tier (e.g. Mail.ReadWrite, Files.ReadWrite.All, Sites.Read.All, Chat.Read.All)</td><td>25 to 40, forces at least High</td></tr>
        <tr><td>Delegated permission</td><td>Catalog weight x0.5 (admin consent for all users) or x0.3 (individual user consent)</td></tr>
        <tr><td>Entra ID directory role held by the service principal</td><td>15 to 70, privileged roles force Critical</td></tr>
        <tr><td>Client secret in use / more than one active secret</td><td>+8 / +5</td></tr>
        <tr><td>Secret lifetime above 12 months / above 24 months or no expiry</td><td>+8 / +15</td></tr>
        <tr><td>Secret stored directly on the service principal</td><td>+20, forces at least Medium</td></tr>
        <tr><td>Expired credentials never removed</td><td>+3</td></tr>
        <tr><td>No owner / guest owner / unverified third-party publisher / multi-tenant with app permissions</td><td>+8 / +10 / +10 / +5</td></tr>
        <tr><td>Implicit grant enabled / non-HTTPS redirect URI / wildcard redirect URI</td><td>+5 / +5 / +8</td></tr>
        <tr><td>Inactive (no sign-in within the configured window) while holding permissions</td><td>+8 to +15</td></tr>
        <tr><td>Service principal disabled</td><td>Score x0.3, level floors removed</td></tr>
        <tr><td>Guard rail: hygiene, governance and configuration factors alone cannot reach Critical</td><td>Critical requires a Critical-tier capability or 40+ permission points, otherwise capped at High</td></tr>
      </table>
      <p style="color:var(--muted)">Limits: Exchange Online RBAC for Applications and Application Access Policies cannot be read through Microsoft Graph, so mailbox permissions scoped that way still appear tenant-wide here. Eligible (PIM) role assignments are not included. The score is a prioritisation aid, not a verdict: validate each Critical and High finding with the application owner.</p>
    </div>
  </section>
</main>
<footer>Generated by Invoke-EntraAppRiskAudit.ps1 | CloudSecOp.com</footer>

<script id="data" type="application/json">__DATA__</script>
<script>
(function(){
const D = JSON.parse(document.getElementById('data').textContent);
const apps = D.apps || [];
const RANK = {Secure:0,Low:1,Medium:2,High:3,Critical:4};
const COLOR = {Critical:'var(--critical)',High:'var(--high)',Medium:'var(--medium)',Low:'var(--low)',Secure:'var(--secure)'};
const el = (tag, attrs, ...kids) => { const e = document.createElement(tag);
  if (attrs) for (const [k,v] of Object.entries(attrs)) { if (k==='class') e.className=v; else if (k==='text') e.textContent=v; else if (k==='style') e.style.cssText=v; else e.setAttribute(k,v); }
  for (const k of kids.flat()) { if (k==null) continue; e.append(k instanceof Node ? k : document.createTextNode(String(k))); } return e; };
const fmtDate = s => s ? s.substring(0,10) : '';
const daysAgo = s => s ? Math.floor((Date.now()-Date.parse(s))/86400000) : null;
const badge = lv => el('span',{class:'badge b-'+lv.toLowerCase(),text:lv});
const tierTag = t => el('span',{class:'badge t-'+String(t||'info').toLowerCase(),text:t});
const authChip = a => { const m={'Secret':'secret','Certificate':'cert','Federated':'fed','Managed Identity':'mi'}; return el('span',{class:'chip '+(m[a]||'none'),text:a}); };
const arr = x => Array.isArray(x) ? x : (x==null ? [] : [x]);
apps.forEach(a => { ['auth','owners','appPerms','delPerms','roles','requested','creds','findings'].forEach(k => a[k]=arr(a[k])); });

// Header
const t = D.tenant || {};
document.getElementById('meta').textContent =
  `Tenant: ${t.DisplayName||''} (${t.Domain||''}) | Tenant ID: ${t.Id||''} | Generated: ${(D.generated||'').replace('T',' ').replace('Z',' UTC')}` +
  ` | Microsoft first-party apps: ${D.options.includeMicrosoft?'included':'excluded'} | Sign-in activity: ${D.options.signInActivity?'included':'not collected'}`;

// KPIs
const exp = arr(D.options.expiry);
const allCreds = apps.flatMap(a => a.creds.map(c => Object.assign({app:a.name, level:a.level}, c)));
const cnt = lv => apps.filter(a => a.level===lv).length;
const kpis = [
  ['Applications', apps.length, '', null],
  ['Critical', cnt('Critical'), 'critical', 'Critical'], ['High', cnt('High'), 'high', 'High'],
  ['Medium', cnt('Medium'), 'medium', 'Medium'], ['Low', cnt('Low'), 'low', 'Low'], ['Secure', cnt('Secure'), 'secure', 'Secure'],
  ['Using secrets', apps.filter(a => a.auth.includes('Secret')).length, 'warn', null],
  [`Expiring < ${exp[0]} d`, allCreds.filter(c => c.d!=null && c.d>=0 && c.d<=exp[0]).length, 'critical', null],
  ['Expired creds', allCreds.filter(c => c.st==='Expired').length, 'high', null],
  ['No owner', apps.filter(a => a.owners.length===0 && /Registered|Enterprise|Registration/.test(a.category)).length, 'medium', null]
];
if (D.options.signInActivity) kpis.push(['Inactive', apps.filter(a => a.findings.some(f => f.a==='Activity')).length, 'low', null]);
const kp = document.getElementById('kpis');
kpis.forEach(([l,v,c,lv]) => { const k = el('div',{class:'kpi '+c+(lv?' clickable':'')}, el('div',{class:'v',text:v}), el('div',{class:'l',text:l}));
  if (lv) k.onclick = () => { document.getElementById('fLevel').value = lv; render(); }; kp.append(k); });

// Category filter
const cats = [...new Set(apps.map(a => a.category))].sort();
cats.forEach(c => document.getElementById('fCat').append(el('option',{text:c})));

// Apps table
let sortKey='score', sortDir=-1;
const tbody = document.querySelector('#appTable tbody');
const sortVal = (a,k) => { switch(k){
  case 'level': return RANK[a.level]*1000+a.score; case 'score': return a.score; case 'auth': return a.auth.join(','); case 'owners': return a.owners.length;
  case 'appPerms': case 'delPerms': case 'roles': return a[k].length;
  case 'nextExpiry': return a.nextExpiry==null ? 99999 : a.nextExpiry; case 'lastSignIn': return a.lastSignIn||'';
  default: return (a[k]??'').toString().toLowerCase(); } };
const matches = (a,q) => !q || [a.name,a.appId,a.spId,a.category,a.publisher,...a.owners,...a.appPerms.map(p=>p.p),...a.delPerms.map(p=>p.p),...a.roles.map(r=>r.n)]
  .some(x => x && String(x).toLowerCase().includes(q));

function permCell(list){
  if (!list.length) return el('span',{class:'empty',text:'0'});
  const risky = list.filter(p => p.t==='Critical'||p.t==='High');
  return el('span',null, String(list.length), risky.length ? el('span',{class:'badge t-'+(risky.some(p=>p.t==='Critical')?'critical':'high'),style:'margin-left:6px',text:risky.length+' risky'}) : null);
}

function detailPanel(a){
  const sevOrder = ['critical','high','medium','low','info'];
  const fRows = a.findings.length ? a.findings.map(f => el('tr',null, el('td',null,tierTag(f.s.charAt(0).toUpperCase()+f.s.slice(1))), el('td',{text:f.a}), el('td',{text:f.d}), el('td',{class:'pts'+(f.pts<0?' neg':''),text:(f.pts>0?'+':'')+f.pts})))
                              : [el('tr',null, el('td',{colspan:4,class:'empty',text:'No risk factor found'}))];
  const pTable = (list, del) => list.length ? el('table',null, el('tr',null, el('th',{text:'Tier'}), el('th',{text:'Permission'}), el('th',{text:'Resource'}), del?el('th',{text:'Consent'}):null, el('th',{text:'Why it matters'})),
       list.slice().sort((x,y)=>(RANK[y.t]??-1)-(RANK[x.t]??-1)).map(p => el('tr',null, el('td',null,tierTag(p.t)), el('td',null, el('b',{text:p.p})), el('td',{text:p.r}), del?el('td',{text:p.c}):null, el('td',{text:p.why||''}))))
     : el('div',{class:'empty',text:'None'});
  const cTable = a.creds.length ? el('table',null, el('tr',null, el('th',{text:'Type'}), el('th',{text:'Stored on'}), el('th',{text:'Name'}), el('th',{text:'Expires'}), el('th',{text:'Status'})),
       a.creds.map(c => el('tr',null, el('td',{text:c.ty}), el('td',{text:c.src}), el('td',{text:c.n}), el('td',{text:fmtDate(c.end)}), el('td',null, statusBadge(c)))))
     : el('div',{class:'empty',text:'No credential stored in this tenant'});
  const rq = a.requested.length ? el('table',null, el('tr',null, el('th',{text:'Permission'}), el('th',{text:'Type'}), el('th',{text:'Resource'})),
       a.requested.map(p => el('tr',null, el('td',{text:p.p}), el('td',{text:p.ty}), el('td',{text:p.r})))) : el('div',{class:'empty',text:'None'});
  const roles = a.roles.length ? el('table',null, a.roles.map(r => el('tr',null, el('td',null, el('b',{text:r.n})), el('td',{text:'scope '+r.s})))) : el('div',{class:'empty',text:'None'});
  return el('div',{class:'dgrid'},
    el('div',{class:'panel',style:'grid-column:1/-1'}, el('h4',{text:`Score breakdown: ${a.score} / 100`}), el('table',null, el('tr',null, el('th',{text:'Severity'}), el('th',{text:'Area'}), el('th',{text:'Finding'}), el('th',{text:'Points'})), fRows)),
    el('div',{class:'panel'}, el('h4',{text:`Application permissions (granted, ${a.appPerms.length})`}), pTable(a.appPerms,false)),
    el('div',{class:'panel'}, el('h4',{text:`Delegated permissions (granted, ${a.delPerms.length})`}), pTable(a.delPerms,true)),
    el('div',{class:'panel'}, el('h4',{text:'Directory roles'}), roles),
    el('div',{class:'panel'}, el('h4',{text:'Credentials'}), cTable),
    el('div',{class:'panel'}, el('h4',{text:'Requested in manifest but not consented'}), rq),
    el('div',{class:'panel'}, el('h4',{text:'Identifiers'}), el('div',{class:'ids'},
       'App ID: '+a.appId, el('br'), 'Application object ID: '+(a.appObjId||'n/a'), el('br'), 'Service principal ID: '+(a.spId||'n/a'), el('br'),
       'Publisher: '+(a.publisher||'n/a'), el('br'), 'Sign-in audience: '+(a.audience||'n/a'), el('br'), 'Created: '+(fmtDate(a.created)||'n/a'), el('br'),
       'Enabled: '+a.enabled, el('br'), 'Owners: '+(a.owners.join(', ')||'none')))
  );
}

function statusBadge(c){
  let cls='st-ok';
  if (c.st==='Expired') cls='st-Expired'; else if (c.st==='No expiry') cls='st-noexp';
  else if (c.d!=null && c.d<=exp[0]) cls='st-crit'; else if (c.d!=null && c.d<=exp[1]) cls='st-warn'; else if (c.d!=null && c.d<=exp[2]) cls='st-notice';
  return el('span',{class:'badge '+cls,text:c.st});
}

let expandedAll=false;
function render(){
  const q = document.getElementById('q').value.trim().toLowerCase();
  const fl = document.getElementById('fLevel').value, fa = document.getElementById('fAuth').value, fc = document.getElementById('fCat').value;
  const list = apps.filter(a => (!fl||a.level===fl) && (!fa||a.auth.includes(fa)) && (!fc||a.category===fc) && matches(a,q))
                   .sort((x,y) => { const a=sortVal(x,sortKey), b=sortVal(y,sortKey); return (a<b?-1:a>b?1:0)*sortDir; });
  tbody.replaceChildren();
  list.forEach(a => {
    const ls = a.lastSignIn ? `${fmtDate(a.lastSignIn)} (${daysAgo(a.lastSignIn)} d)` : (D.options.signInActivity ? 'Never' : 'n/a');
    const ne = a.nextExpiry==null ? '' : (a.nextExpiry+' d');
    const tr = el('tr',{class:'row lv-'+a.level},
      el('td',null,badge(a.level)),
      el('td',null, el('div',{class:'score',style:'color:'+COLOR[a.level],text:a.score}), el('div',{class:'bar'}, el('span',{style:`width:${a.score}%;background:${COLOR[a.level]}`}))),
      el('td',null, el('div',{class:'name',text:a.name}), el('div',{class:'sub',text:a.appId}), a.enabled===false? el('span',{class:'badge t-info',text:'Disabled'}):null),
      el('td',{text:a.category}),
      el('td',null, a.auth.map(authChip)),
      el('td',null, permCell(a.appPerms)), el('td',null, permCell(a.delPerms)),
      el('td',null, a.roles.length ? el('span',{class:'badge t-critical',text:a.roles.length}) : el('span',{class:'empty',text:'0'})),
      el('td',null, a.owners.length ? a.owners.join(', ') : el('span',{class:'empty',text:'none'})),
      el('td',{text:ls}), el('td',{text:ne}));
    const dt = el('tr',{class:'detail'+(expandedAll?'':' hidden')}, el('td',{colspan:11}));
    let built=false;
    const build = () => { if(!built){ dt.firstChild.append(detailPanel(a)); built=true; } };
    if (expandedAll) build();
    tr.onclick = () => { build(); dt.classList.toggle('hidden'); };
    tbody.append(tr, dt);
  });
  document.getElementById('count').textContent = `${list.length} of ${apps.length} applications`;
  document.querySelectorAll('#appTable th').forEach(th => { th.classList.remove('sorted-asc','sorted-desc'); if (th.dataset.k===sortKey) th.classList.add(sortDir>0?'sorted-asc':'sorted-desc'); });
}
document.querySelectorAll('#appTable th').forEach(th => th.onclick = () => { const k=th.dataset.k; if (sortKey===k) sortDir=-sortDir; else { sortKey=k; sortDir=(k==='name'||k==='category'||k==='nextExpiry')?1:-1; } render(); });
['q','fLevel','fAuth','fCat'].forEach(id => document.getElementById(id).addEventListener('input', render));
document.getElementById('expandAll').onclick = e => { expandedAll=!expandedAll; e.target.textContent = expandedAll?'Collapse all':'Expand all'; render(); };

// Credentials tab
const credList = allCreds.filter(c => c.ty!=='Federated').sort((a,b) => (a.d??99999)-(b.d??99999));
const statuses = [...new Set(credList.map(c=>c.st))]; const types=[...new Set(credList.map(c=>c.ty))];
statuses.forEach(s => document.getElementById('fStatus').append(el('option',{text:s})));
types.forEach(s => document.getElementById('fType').append(el('option',{text:s})));
function renderCreds(){
  const fs=document.getElementById('fStatus').value, ft=document.getElementById('fType').value;
  const list = credList.filter(c => (!fs||c.st===fs)&&(!ft||c.ty===ft));
  const tb = document.querySelector('#credTable tbody'); tb.replaceChildren();
  list.forEach(c => tb.append(el('tr',null, el('td',null,statusBadge(c)), el('td',{class:'pts',text:c.d==null?'':c.d}), el('td',null, el('b',{text:c.app})),
      el('td',{text:c.ty}), el('td',{text:c.src}), el('td',{text:c.n}), el('td',{text:fmtDate(c.end)}), el('td',{text:c.life?c.life+' d':''}), el('td',null,badge(c.level)))));
  document.getElementById('ccount').textContent = `${list.length} credentials`;
}
['fStatus','fType'].forEach(id => document.getElementById(id).addEventListener('input', renderCreds));

// Tabs
document.querySelectorAll('.tab').forEach(b => b.onclick = () => {
  document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active', x===b));
  ['apps','creds','method'].forEach(n => document.getElementById('tab-'+n).classList.toggle('hidden', n!==b.dataset.tab));
});
render(); renderCreds();
})();
</script>
</body>
</html>
'@
    $html = $html.Replace('__DATA__', $json)
    Set-Content -Path $Path -Value $html -Encoding utf8
}

function Export-FlatFiles {
    param($Results, [string]$BasePath)

    $Results | ForEach-Object {
        [pscustomobject]@{
            Level = $_.Level; Score = $_.Score; DisplayName = $_.DisplayName; AppId = $_.AppId; Category = $_.Category
            AuthModes = ($_.AuthModes -join ';'); Publisher = $_.Publisher; Enabled = $_.Enabled
            AppPermissions = (@($_.ApplicationPermissions | ForEach-Object Permission) -join ';')
            DelegatedPermissions = (@($_.DelegatedPermissions | ForEach-Object Permission) -join ';')
            DirectoryRoles = (@($_.DirectoryRoles | ForEach-Object Role) -join ';')
            Owners = ($_.Owners -join ';'); LastSignIn = $(if ($_.LastSignIn) { $_.LastSignIn.ToString('yyyy-MM-dd') } else { '' }); NextExpiryDays = $_.NextExpiryDays
            TopFindings = (@($_.Findings | Select-Object -First 3 | ForEach-Object { "$($_.Points): $($_.Detail)" }) -join ' | ')
        }
    } | Export-Csv -Path "$BasePath`_Apps.csv" -NoTypeInformation -Encoding utf8

    $Results | ForEach-Object { $a = $_; $a.Credentials | ForEach-Object {
        [pscustomobject]@{ DisplayName = $a.DisplayName; AppId = $a.AppId; AppLevel = $a.Level; Type = $_.Type; StoredOn = $_.Source
                           Name = $_.Name; KeyId = $_.KeyId
                           Start = if ($_.Start) { $_.Start.ToString('yyyy-MM-dd') } else { '' }
                           End   = if ($_.End)   { $_.End.ToString('yyyy-MM-dd') } else { '' }; DaysLeft = $_.DaysLeft; LifetimeDays = $_.LifetimeDays; Status = $_.Status } } } |
        Sort-Object { if ($null -eq $_.DaysLeft) { 99999 } else { $_.DaysLeft } } |
        Export-Csv -Path "$BasePath`_Credentials.csv" -NoTypeInformation -Encoding utf8

    $Results | ForEach-Object { $a = $_; @($a.ApplicationPermissions) + @($a.DelegatedPermissions) | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ DisplayName = $a.DisplayName; AppId = $a.AppId; AppLevel = $a.Level; Type = $_.Type; Permission = $_.Permission
                           Resource = $_.Resource; Tier = $_.Tier; Consent = Get-Prop $_ 'Consent' 'Admin (application)'; Reason = $_.Reason } } } |
        Export-Csv -Path "$BasePath`_Permissions.csv" -NoTypeInformation -Encoding utf8

    $Results | ConvertTo-Json -Depth 8 | Set-Content -Path "$BasePath.json" -Encoding utf8
}

#endregion

#region ===================== Main =====================

$script:SignInActivityFailed = $false
$script:ParamSetName = $PSCmdlet.ParameterSetName
$sw = [Diagnostics.Stopwatch]::StartNew()

Connect-AuditGraph
$data    = Get-AuditData
Write-Step 'Scoring applications'
$results = Invoke-AuditAnalysis -Data $data

if (-not (Test-Path $OutputPath)) { New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null }
$stamp    = Get-Date -Format 'yyyyMMdd_HHmm'
$basePath = Join-Path $OutputPath "EntraAppAudit_$stamp"
$htmlPath = "$basePath.html"

Write-Step 'Writing HTML report and exports'
New-HtmlReport -Results $results -Tenant $data.Tenant -Path $htmlPath
Export-FlatFiles -Results $results -BasePath $basePath

# Console summary
$summary = $results | Group-Object Level | ForEach-Object { [pscustomobject]@{ Level = $_.Name; Count = $_.Count } } |
           Sort-Object { $script:LevelRank[$_.Level] } -Descending
Write-Host ''
Write-Host "=== Entra ID application risk summary ($($results.Count) applications, $([int]$sw.Elapsed.TotalSeconds) s) ===" -ForegroundColor White
$colors = @{ Critical = 'Red'; High = 'DarkYellow'; Medium = 'Yellow'; Low = 'Blue'; Secure = 'Green' }
foreach ($s in $summary) { Write-Host ("  {0,-9} {1,5}" -f $s.Level, $s.Count) -ForegroundColor $colors[$s.Level] }
$soon = @($results | ForEach-Object { $_.Credentials } | Where-Object { $null -ne $_.DaysLeft -and $_.DaysLeft -ge 0 -and $_.DaysLeft -le $ExpiryCriticalDays })
if ($soon.Count) { Write-Host "  $($soon.Count) credential(s) expiring within $ExpiryCriticalDays days" -ForegroundColor Red }
Write-Host ''
Write-Host "Report : $htmlPath" -ForegroundColor Green
Write-Host "Exports: $basePath`_Apps.csv | _Credentials.csv | _Permissions.csv | .json" -ForegroundColor Green

#endregion
