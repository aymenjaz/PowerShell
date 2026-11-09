<#
.SYNOPSIS
    READ-ONLY diagnostic of Windows Autopilot device preparation (Autopilot v2) using Microsoft Graph.

.DESCRIPTION
    Checks tenant-side prerequisites and configuration for Autopilot device preparation (DPP):
      1. Tenant prerequisites: "Intune Provisioning Client" SP, MDM user scope, Entra join permission
      2. User: account, Intune / Entra P1 licenses, groups, Entra and Intune device quotas
      3. Windows enrollment restrictions and Conditional Access (chicken-and-egg blockers)
      4. DPP policies: settings, assignments, user targeting, app/script limits
      5. Device group (Enrollment time grouping): membership type, Intune Provisioning Client ownership
      6. Allowed apps and scripts: existence, Required assignment to the device group, run context
      7. Device: Autopilot v1 conflict, corporate identifier, Intune / Entra objects, device group membership
      8. Intune enrollment failure events (troubleshootingEvents)

    Read-only guarantees:
      - Only *.Read.All scopes are requested: the token cannot write anything.
      - Every request goes through the Get-Graph function, which ONLY issues GET calls.
        Quick check: Select-String -Path .\Test-AutopilotDevicePrep-EN.ps1 -Pattern '-Method'

.PARAMETER UserPrincipalName
    UPN of the enrolling user. Enables license, group, quota, CA and event checks.
.PARAMETER SerialNumber
    Device serial number. Enables v1 conflict, corporate identifier, Intune/Entra object and group checks.
.PARAMETER PolicyName
    Filter (wildcards allowed, e.g. "DPP*") on the Autopilot device preparation policy name.
.PARAMETER DeviceGroupId
    ObjectId of one or more device groups. Otherwise, detected through the groups owned by
    Intune Provisioning Client.
.PARAMETER TenantId
    Target tenant (optional).
.PARAMETER LookbackDays
    Time window for enrollment failure events (default: 14 days).
.PARAMETER ExportPath
    LOCAL folder for the HTML and CSV report (nothing is written to the tenant).
.PARAMETER PassThru
    Also returns the results as PowerShell objects.

.EXAMPLE
    .\Test-AutopilotDevicePrep-EN.ps1 -UserPrincipalName jdoe@contoso.org -SerialNumber 5CG1234XYZ -ExportPath C:\Temp

.NOTES
    Required module: Microsoft.Graph.Authentication (v2+)
    Recommended roles: Intune "Read Only Operator" + Entra "Global Reader"
    (Global Reader or Security Reader is required to read Conditional Access policies).
#>

#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication

[CmdletBinding()]
param(
    [string]$UserPrincipalName,
    [string]$SerialNumber,
    [string]$PolicyName,
    [string[]]$DeviceGroupId,
    [string]$TenantId,
    [ValidateRange(1, 90)][int]$LookbackDays = 14,
    [string]$ExportPath,
    [switch]$PassThru
)

#region Constants
$Graph = 'https://graph.microsoft.com'

$Const = @{
    ProvisioningClientAppId = 'f1346770-5b25-470b-88bd-d5744ab7952c'   # Intune Provisioning Client
    IntuneMdmAppId          = '0000000a-0000-0000-c000-000000000000'   # Microsoft Intune
    IntuneEnrollmentAppId   = 'd4ebce55-015a-49b5-a083-c84d1797ae8c'   # Microsoft Intune Enrollment
    PlanIntune              = 'c1ec4a95-1f05-45b3-a911-aa3fa01094f5'   # INTUNE_A
    PlanEntraP1             = '41781fb2-bc02-4b7c-bd55-b576c07bb09d'   # AAD_PREMIUM
    PlanEntraP2             = 'eec0eb4f-6444-4f95-aba0-50c24d67f998'   # AAD_PREMIUM_P2
    MaxApps                 = 25    # Current DPP limit, adjust if Microsoft changes it
    MaxScripts              = 10
    MinBuild                = 22621 # Windows 11 22H2
    MinUbr2262x             = 3374  # KB5035942 (March 2024) for 22621 / 22631
}

# Read-only scopes
$Scopes = @(
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementServiceConfig.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementApps.Read.All',
    'Group.Read.All',
    'GroupMember.Read.All',
    'User.Read.All',
    'Device.Read.All',
    'Policy.Read.All',
    'Application.Read.All',
    'Directory.Read.All'
)

# DPP setting labels (settingDefinitionId)
$SettingLabels = @{
    'enrollment_autopilot_dpp_deploymentmode'     = 'Deployment mode'
    'enrollment_autopilot_dpp_deploymenttype'     = 'Deployment type'
    'enrollment_autopilot_dpp_jointype'           = 'Join type'
    'enrollment_autopilot_dpp_accountype'         = 'User account type'
    'enrollment_autopilot_dpp_timeout'            = 'Installation timeout (minutes)'
    'enrollment_autopilot_dpp_customerrormessage' = 'Custom error message'
    'enrollment_autopilot_dpp_allowskip'          = 'Allow users to skip'
    'enrollment_autopilot_dpp_allowdiagnostics'   = 'Allow diagnostics collection'
}

# Observed choice values, validate in the Intune portal
$ChoiceLabels = @{
    'enrollment_autopilot_dpp_deploymentmode_0' = 'User-driven'
    'enrollment_autopilot_dpp_deploymentmode_1' = 'Automatic'
    'enrollment_autopilot_dpp_accountype_0'     = 'Standard user'
    'enrollment_autopilot_dpp_accountype_1'     = 'Administrator'
    'enrollment_autopilot_dpp_jointype_0'       = 'Microsoft Entra joined'
}
#endregion

#region Helper functions
$script:Results = [System.Collections.Generic.List[object]]::new()
$GroupNameCache = @{}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor White
}

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL', 'INFO', 'SKIP')][string]$Status,
        [string]$Detail = '',
        [string]$Remediation = ''
    )
    $script:Results.Add([pscustomobject]@{
            Status      = $Status
            Category    = $Category
            Check       = $Check
            Detail      = $Detail
            Remediation = $Remediation
        })
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Cyan'; SKIP = 'DarkGray' }[$Status]
    Write-Host ("  [{0}] {1} : {2}" -f $Status.PadRight(4), $Check, $Detail) -ForegroundColor $color
    if ($Remediation -and ($Status -in 'FAIL', 'WARN')) {
        Write-Host ("         -> {0}" -f $Remediation) -ForegroundColor DarkYellow
    }
}

function Get-Graph {
    <#
        Single Graph entry point for the script: GET only, with paging.
        Returns { Ok ; Data ; Error } to distinguish "empty" from "error".
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Category = 'Graph',
        [string]$Check = 'Graph request',
        [switch]$Quiet
    )
    $items = [System.Collections.Generic.List[object]]::new()
    $single = $null
    $next = $Uri
    try {
        while ($next) {
            $resp = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
            if ($resp.PSObject.Properties.Name -contains 'value') {
                foreach ($i in @($resp.value)) { if ($null -ne $i) { $items.Add($i) } }
                $next = $resp.'@odata.nextLink'
            }
            else {
                $single = $resp
                $next = $null
            }
        }
        $data = if ($null -ne $single) { $single } else { $items.ToArray() }
        return [pscustomobject]@{ Ok = $true; Data = $data; Error = $null }
    }
    catch {
        $msg = ($_.Exception.Message -split "`n")[0]
        if (-not $Quiet) {
            Add-Result -Category $Category -Check $Check -Status 'SKIP' -Detail "Graph call failed: $msg" `
                -Remediation 'Check the token scopes and the operator Intune / Entra role.'
        }
        return [pscustomobject]@{ Ok = $false; Data = $null; Error = $msg }
    }
}

function Get-GroupName {
    param([string]$Id)
    if (-not $Id) { return '' }
    if ($GroupNameCache.ContainsKey($Id)) { return $GroupNameCache[$Id] }
    $r = Get-Graph -Uri "$Graph/v1.0/groups/$($Id)?`$select=id,displayName" -Quiet
    $name = if ($r.Ok -and $r.Data.displayName) { $r.Data.displayName } else { "$Id (not found)" }
    $GroupNameCache[$Id] = $name
    return $name
}

function Get-SettingValues {
    # Recursively flattens a Settings Catalog settingInstance: definitionId -> values
    param($Instance, [hashtable]$Map)
    if (-not $Instance) { return }
    $id = [string]$Instance.settingDefinitionId
    $vals = [System.Collections.Generic.List[string]]::new()

    if ($Instance.choiceSettingValue) {
        $vals.Add([string]$Instance.choiceSettingValue.value)
        foreach ($c in @($Instance.choiceSettingValue.children)) { Get-SettingValues -Instance $c -Map $Map }
    }
    if ($Instance.simpleSettingValue) { $vals.Add([string]$Instance.simpleSettingValue.value) }
    foreach ($v in @($Instance.simpleSettingCollectionValue)) { if ($v) { $vals.Add([string]$v.value) } }
    foreach ($v in @($Instance.choiceSettingCollectionValue)) {
        if ($v) {
            $vals.Add([string]$v.value)
            foreach ($c in @($v.children)) { Get-SettingValues -Instance $c -Map $Map }
        }
    }
    if ($Instance.groupSettingValue) {
        foreach ($c in @($Instance.groupSettingValue.children)) { Get-SettingValues -Instance $c -Map $Map }
    }
    foreach ($g in @($Instance.groupSettingCollectionValue)) {
        if ($g) { foreach ($c in @($g.children)) { Get-SettingValues -Instance $c -Map $Map } }
    }

    if ($id -and $vals.Count -gt 0) {
        if (-not $Map.ContainsKey($id)) { $Map[$id] = [System.Collections.Generic.List[string]]::new() }
        $Map[$id].AddRange($vals)
    }
}

function Get-Guids {
    param([string[]]$Text)
    $rx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $Text) {
        foreach ($m in [regex]::Matches([string]$t, $rx)) { [void]$set.Add($m.Value) }
    }
    return , @($set)
}

function Test-TargetsUser {
    # Returns 'Included', 'Excluded' or 'NotTargeted' for a list of Intune assignments
    param($Assignments, $UserGroupIds)
    $included = $false; $excluded = $false
    foreach ($a in @($Assignments)) {
        if (-not $a) { continue }
        $t = $a.target
        switch ($t.'@odata.type') {
            '#microsoft.graph.allLicensedUsersAssignmentTarget' { $included = $true }
            '#microsoft.graph.groupAssignmentTarget' { if ($UserGroupIds.Contains([string]$t.groupId)) { $included = $true } }
            '#microsoft.graph.exclusionGroupAssignmentTarget' { if ($UserGroupIds.Contains([string]$t.groupId)) { $excluded = $true } }
        }
    }
    if ($excluded) { 'Excluded' } elseif ($included) { 'Included' } else { 'NotTargeted' }
}

function Resolve-EffectiveConfig {
    # Enrollment restrictions: the highest priority custom config (1 = strongest) targeting
    # the user wins, otherwise the default config (priority 0)
    param([object[]]$Configs, $UserGroupIds)
    $custom = @($Configs | Where-Object { [int]$_.priority -gt 0 } | Sort-Object { [int]$_.priority })
    foreach ($c in $custom) {
        if ((Test-TargetsUser -Assignments $c.assignments -UserGroupIds $UserGroupIds) -eq 'Included') { return $c }
    }
    return ($Configs | Where-Object { [int]$_.priority -eq 0 } | Select-Object -First 1)
}

function Format-Targets {
    param($Assignments)
    $inc = @(); $exc = @()
    foreach ($a in @($Assignments)) {
        if (-not $a) { continue }
        $t = $a.target
        $label = if ($t.groupId) { Get-GroupName -Id $t.groupId } else { ($t.'@odata.type' -replace '#microsoft.graph.', '') }
        if ($t.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget') { $exc += $label } else { $inc += $label }
    }
    "Included: {0} | Excluded: {1}" -f ($(if ($inc) { $inc -join ', ' } else { 'none' })), ($(if ($exc) { $exc -join ', ' } else { 'none' }))
}
#endregion

#region Connection
Write-Host ''
Write-Host 'Autopilot device preparation (v2): read-only diagnostic' -ForegroundColor White
Write-Host ('Run on {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray

$ctx = Get-MgContext
if (-not $ctx) {
    $cp = @{ Scopes = $Scopes; NoWelcome = $true }
    if ($TenantId) { $cp.TenantId = $TenantId }
    Connect-MgGraph @cp | Out-Null
    $ctx = Get-MgContext
}
if (-not $ctx) { throw 'Unable to connect to Microsoft Graph.' }

$missingScopes = @($Scopes | Where-Object { $ctx.Scopes -notcontains $_ })
if ($missingScopes.Count -gt 0 -and $ctx.AuthType -eq 'Delegated') {
    Write-Warning ("Scopes missing from the token: {0}. Related checks will be marked SKIP. To fix: Disconnect-MgGraph and run again." -f ($missingScopes -join ', '))
}
$writeScopes = @($ctx.Scopes | Where-Object { $_ -match 'ReadWrite' })
if ($writeScopes.Count -gt 0) {
    Write-Warning ("The current token includes write scopes ({0}). The script only issues GET calls, but for a strict guarantee, reconnect with read-only scopes." -f ($writeScopes -join ', '))
}
#endregion

#region 1. Tenant prerequisites
Write-Section '1. Tenant prerequisites'

$org = Get-Graph -Uri "$Graph/v1.0/organization?`$select=id,displayName" -Quiet
if ($org.Ok -and @($org.Data).Count -gt 0) {
    Add-Result 'Tenant' 'Tenant' 'INFO' ("{0} ({1}), account: {2}" -f @($org.Data)[0].displayName, @($org.Data)[0].id, $ctx.Account)
}

# 1.1 Intune Provisioning Client service principal
$spProv = $null
$r = Get-Graph -Uri "$Graph/v1.0/servicePrincipals?`$filter=appId eq '$($Const.ProvisioningClientAppId)'&`$select=id,appId,displayName,accountEnabled" `
    -Category 'Tenant' -Check 'Intune Provisioning Client SP'
if ($r.Ok) {
    $spProv = @($r.Data) | Select-Object -First 1
    if (-not $spProv) {
        Add-Result 'Tenant' 'Intune Provisioning Client SP' 'FAIL' "Service principal missing from the tenant (AppId $($Const.ProvisioningClientAppId))." `
            "Write action to perform outside this script: New-MgServicePrincipal -AppId $($Const.ProvisioningClientAppId)"
    }
    elseif (-not $spProv.accountEnabled) {
        Add-Result 'Tenant' 'Intune Provisioning Client SP' 'FAIL' "SP present but disabled ($($spProv.displayName))." `
            'Re-enable the service principal in Entra > Enterprise applications.'
    }
    else {
        Add-Result 'Tenant' 'Intune Provisioning Client SP' 'PASS' ("{0} present and enabled (objectId {1})" -f $spProv.displayName, $spProv.id)
    }
}

# 1.2 MDM user scope
$mdmAppliesTo = $null
$mdmIncluded = @()
$r = Get-Graph -Uri "$Graph/beta/policies/mobileDeviceManagementPolicies/$($Const.IntuneMdmAppId)" -Category 'Tenant' -Check 'Intune MDM user scope'
if ($r.Ok) {
    $mdmAppliesTo = [string]$r.Data.appliesTo
    switch ($mdmAppliesTo) {
        'all' { Add-Result 'Tenant' 'Intune MDM user scope' 'PASS' 'MDM user scope: All' }
        'selected' {
            $g = Get-Graph -Uri "$Graph/beta/policies/mobileDeviceManagementPolicies/$($Const.IntuneMdmAppId)/includedGroups?`$select=id,displayName" -Quiet
            $mdmIncluded = @($g.Data | ForEach-Object { [string]$_.id })
            $names = @($g.Data | ForEach-Object { $_.displayName }) -join ', '
            Add-Result 'Tenant' 'Intune MDM user scope' 'INFO' "MDM user scope: Some ($names)"
        }
        'none' {
            Add-Result 'Tenant' 'Intune MDM user scope' 'FAIL' 'MDM user scope: None. Automatic enrollment is impossible.' `
                'Entra > Mobility (MDM and MAM) > Microsoft Intune > MDM user scope: All or Some.'
        }
        default { Add-Result 'Tenant' 'Intune MDM user scope' 'INFO' "Returned value: $mdmAppliesTo" }
    }
}

# 1.3 Entra join permission and quota
$djAllowed = $null; $djUsers = @(); $djGroups = @(); $entraQuota = $null
$r = Get-Graph -Uri "$Graph/beta/policies/deviceRegistrationPolicy" -Category 'Tenant' -Check 'Entra device settings'
if ($r.Ok) {
    $entraQuota = $r.Data.userDeviceQuota
    $allowed = $r.Data.azureADJoin.allowedToJoin
    $jt = [string]$allowed.'@odata.type'
    switch -Wildcard ($jt) {
        '*allDeviceRegistrationMembership' {
            $djAllowed = 'all'
            Add-Result 'Tenant' 'Entra join allowed' 'PASS' 'Users may join devices: All'
        }
        '*enumeratedDeviceRegistrationMembership' {
            $djAllowed = 'selected'
            $djUsers = @($allowed.users | ForEach-Object { [string]$_ })
            $djGroups = @($allowed.groups | ForEach-Object { [string]$_ })
            Add-Result 'Tenant' 'Entra join allowed' 'INFO' ("Selected: {0} user(s), {1} group(s)" -f $djUsers.Count, $djGroups.Count)
        }
        '*noDeviceRegistrationMembership' {
            $djAllowed = 'none'
            Add-Result 'Tenant' 'Entra join allowed' 'FAIL' 'No user may join devices to Entra.' `
                'Entra > Devices > Device settings: allow join (All or Selected).'
        }
        default { Add-Result 'Tenant' 'Entra join allowed' 'INFO' "Unrecognized type: $jt" }
    }
    Add-Result 'Tenant' 'Entra device quota' 'INFO' ("{0} device(s) max per user" -f $entraQuota)
    if ($r.Data.multiFactorAuthConfiguration) {
        Add-Result 'Tenant' 'MFA to join devices' 'INFO' ([string]$r.Data.multiFactorAuthConfiguration)
    }
}
#endregion

#region 2. User
$User = $null
$UserGroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($UserPrincipalName) {
    Write-Section "2. User: $UserPrincipalName"
    $cat = 'User'
    $upnEsc = [uri]::EscapeDataString($UserPrincipalName)
    $r = Get-Graph -Uri "$Graph/v1.0/users/$($upnEsc)?`$select=id,displayName,userPrincipalName,accountEnabled,usageLocation,userType" `
        -Category $cat -Check 'Account lookup'
    if ($r.Ok) { $User = $r.Data }

    if ($User) {
        if ($User.accountEnabled) { Add-Result $cat 'Account' 'PASS' ("{0} enabled (id {1})" -f $User.displayName, $User.id) }
        else { Add-Result $cat 'Account' 'FAIL' 'Account disabled.' 'Re-enable the account.' }

        if ($User.userType -eq 'Guest') {
            Add-Result $cat 'Account type' 'FAIL' 'Guest account: not supported for Autopilot enrollment.' 'Use a member account of the tenant.'
        }
        if (-not $User.usageLocation) {
            Add-Result $cat 'Usage location' 'WARN' 'No usageLocation set.' 'Set usageLocation, otherwise license assignment may fail.'
        }

        # Licenses
        $r = Get-Graph -Uri "$Graph/v1.0/users/$($User.id)/licenseDetails" -Category $cat -Check 'Licenses'
        if ($r.Ok) {
            $plans = @($r.Data | ForEach-Object { $_.servicePlans })
            $pIntune = @($plans | Where-Object { $_.servicePlanId -eq $Const.PlanIntune })
            if ($pIntune.Count -eq 0) {
                Add-Result $cat 'Intune license' 'FAIL' 'No INTUNE_A service plan assigned.' 'Assign a license that includes Intune (M365 BP / E3 / E5, EMS, Intune P1...).'
            }
            elseif (@($pIntune | Where-Object { $_.provisioningStatus -eq 'Success' }).Count -eq 0) {
                Add-Result $cat 'Intune license' 'WARN' ("INTUNE_A plan present, status: {0}" -f (($pIntune | ForEach-Object { $_.provisioningStatus }) -join ', ')) `
                    'Make sure the Intune service plan is not disabled in the license.'
            }
            else { Add-Result $cat 'Intune license' 'PASS' 'INTUNE_A active' }

            $pEntra = @($plans | Where-Object { ($_.servicePlanId -in $Const.PlanEntraP1, $Const.PlanEntraP2) -and $_.provisioningStatus -eq 'Success' })
            if ($pEntra.Count -gt 0) { Add-Result $cat 'Entra ID P1/P2 license' 'PASS' 'Present (required for automatic MDM enrollment)' }
            else { Add-Result $cat 'Entra ID P1/P2 license' 'WARN' 'No active Entra P1/P2 plan.' 'Automatic MDM enrollment requires Entra ID P1 (included in M365 BP, E3, E5, EMS).' }
        }

        # Groups (transitive)
        $r = Get-Graph -Uri "$Graph/v1.0/users/$($User.id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999" -Category $cat -Check 'Groups'
        if ($r.Ok) {
            foreach ($g in @($r.Data)) { [void]$UserGroupIds.Add([string]$g.id); $GroupNameCache[[string]$g.id] = $g.displayName }
            Add-Result $cat 'Groups' 'INFO' ("Member of {0} group(s) (transitive)" -f $UserGroupIds.Count)
        }

        # MDM scope "Some"
        if ($mdmAppliesTo -eq 'selected') {
            $hit = @($mdmIncluded | Where-Object { $UserGroupIds.Contains($_) })
            if ($hit.Count -gt 0) { Add-Result $cat 'In MDM scope' 'PASS' 'User is a member of an MDM scope group' }
            else { Add-Result $cat 'In MDM scope' 'FAIL' 'User is outside the MDM scope (Some).' 'Add the user to an Intune MDM scope group.' }
        }

        # Join permission "Selected"
        if ($djAllowed -eq 'selected') {
            $ok = ($djUsers -contains $User.id) -or (@($djGroups | Where-Object { $UserGroupIds.Contains($_) }).Count -gt 0)
            if ($ok) { Add-Result $cat 'Allowed to join' 'PASS' 'User is in the Entra join selection' }
            else { Add-Result $cat 'Allowed to join' 'FAIL' 'User is not allowed to join devices to Entra.' 'Entra > Devices > Device settings: add the user or one of their groups.' }
        }

        # Entra quota
        if ($entraQuota -and [int]$entraQuota -gt 0) {
            $r = Get-Graph -Uri "$Graph/v1.0/users/$($User.id)/ownedDevices?`$select=id" -Quiet
            if ($r.Ok) {
                $n = @($r.Data).Count
                if ($n -ge [int]$entraQuota) {
                    Add-Result $cat 'Entra quota' 'FAIL' "$n / $entraQuota owned devices: quota reached." 'Remove stale device objects or raise the quota.'
                }
                else { Add-Result $cat 'Entra quota' 'PASS' "$n / $entraQuota owned devices" }
            }
        }
    }
}
else {
    Write-Section '2. User'
    Add-Result 'User' 'User checks' 'SKIP' '-UserPrincipalName parameter not provided.'
}
#endregion

#region 3. Enrollment restrictions and Conditional Access
Write-Section '3. Enrollment restrictions and Conditional Access'
$personalBlocked = $false
$cat = 'Restrictions'

$r = Get-Graph -Uri "$Graph/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments" -Category $cat -Check 'Reading restrictions'
if ($r.Ok) {
    $cfgs = @($r.Data)

    # Windows platform restrictions (per-platform format + legacy default format)
    $winCfgs = @(@(foreach ($c in $cfgs) {
                $t = [string]$c.'@odata.type'
                if ($t -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration' -and $c.platformType -eq 'windows') {
                    [pscustomobject]@{ displayName = $c.displayName; priority = [int]$c.priority; assignments = $c.assignments; restriction = $c.platformRestriction; order = 0 }
                }
                elseif ($t -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration') {
                    [pscustomobject]@{ displayName = $c.displayName; priority = [int]$c.priority; assignments = $c.assignments; restriction = $c.windowsRestriction; order = 1 }
                }
            }) | Sort-Object priority, order)

    $scopeTxt = if ($User) { "effective for $UserPrincipalName" } else { 'default, no user provided' }
    $effWin = Resolve-EffectiveConfig -Configs $winCfgs -UserGroupIds $UserGroupIds
    if ($effWin) {
        $rs = $effWin.restriction
        if ($rs.platformBlocked) {
            Add-Result $cat 'Windows platform' 'FAIL' "Windows blocked by '$($effWin.displayName)' ($scopeTxt)." 'Intune > Devices > Enrollment > Device platform restrictions.'
        }
        else { Add-Result $cat 'Windows platform' 'PASS' "Allowed by '$($effWin.displayName)' ($scopeTxt)" }

        if ($rs.personalDeviceEnrollmentBlocked) {
            $personalBlocked = $true
            Add-Result $cat 'Personal devices' 'INFO' 'Personal Windows enrollment blocked: each DPP device needs a corporate identifier (checked in section 7 with -SerialNumber).'
        }
        else { Add-Result $cat 'Personal devices' 'INFO' 'Personal Windows enrollment allowed' }

        if ($rs.osMinimumVersion) { Add-Result $cat 'Minimum OS version' 'INFO' $rs.osMinimumVersion }
    }

    # Intune device limit
    $limCfgs = @($cfgs | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.deviceEnrollmentLimitConfiguration' })
    $effLim = Resolve-EffectiveConfig -Configs $limCfgs -UserGroupIds $UserGroupIds
    if ($effLim) {
        $limit = [int]$effLim.limit
        if ($User) {
            $m = Get-Graph -Uri "$Graph/v1.0/users/$($User.id)/managedDevices?`$select=id" -Quiet
            if ($m.Ok) {
                $n = @($m.Data).Count
                if ($n -ge $limit) {
                    Add-Result $cat 'Intune device limit' 'FAIL' "$n / $limit ('$($effLim.displayName)'): limit reached." 'Remove stale devices or raise the limit.'
                }
                else { Add-Result $cat 'Intune device limit' 'PASS' "$n / $limit ('$($effLim.displayName)')" }
            }
        }
        else { Add-Result $cat 'Intune device limit' 'INFO' "$limit ('$($effLim.displayName)')" }
    }
}

# Conditional Access
$cat = 'Conditional Access'
$r = Get-Graph -Uri "$Graph/v1.0/identity/conditionalAccess/policies" -Category $cat -Check 'Reading CA policies'
if ($r.Ok) {
    $found = $false
    foreach ($p in @($r.Data)) {
        if ($p.state -eq 'disabled') { continue }
        $apps = $p.conditions.applications
        $inclApps = @($apps.includeApplications)
        $exclApps = @($apps.excludeApplications)
        $targetsEnroll = (($inclApps -contains 'All') -or ($inclApps -contains $Const.IntuneEnrollmentAppId) -or ($inclApps -contains $Const.IntuneMdmAppId)) -and
                         -not ($exclApps -contains $Const.IntuneEnrollmentAppId)
        $targetsRegister = @($apps.includeUserActions) -contains 'urn:user:registerdevice'
        if (-not ($targetsEnroll -or $targetsRegister)) { continue }

        # User scope (approximation: roles are not evaluated)
        $u = $p.conditions.users
        $scope = 'Unknown'
        if ($User) {
            $incl = ((@($u.includeUsers) -contains 'All') -or (@($u.includeUsers) -contains $User.id) -or
                (@($u.includeGroups | Where-Object { $UserGroupIds.Contains([string]$_) }).Count -gt 0))
            $excl = ((@($u.excludeUsers) -contains $User.id) -or
                (@($u.excludeGroups | Where-Object { $UserGroupIds.Contains([string]$_) }).Count -gt 0))
            $scope = if ($excl) { 'Excluded' } elseif ($incl) { 'Included' } elseif (@($u.includeRoles).Count -gt 0) { 'To verify (roles)' } else { 'Out of scope' }
        }
        if ($scope -in 'Excluded', 'Out of scope') { continue }
        $found = $true

        $grant = @($p.grantControls.builtInControls)
        $deviceBased = ($grant -contains 'compliantDevice') -or ($grant -contains 'domainJoinedDevice')
        $what = @(); if ($targetsEnroll) { $what += 'Intune enrollment' }; if ($targetsRegister) { $what += 'Register or join devices user action' }
        $detail = "'{0}' ({1}) targets {2}, controls: {3}, user scope: {4}" -f $p.displayName, $p.state, ($what -join ' + '), ($(if ($grant) { $grant -join ', ' } else { 'session / auth strength' })), $scope

        if ($deviceBased -and $p.state -eq 'enabled') {
            Add-Result $cat 'Compliant device requirement' 'FAIL' $detail `
                'Chicken-and-egg blocker: exclude the "Microsoft Intune Enrollment" app (d4ebce55-015a-49b5-a083-c84d1797ae8c) and do not require a compliant device on the Register or join devices action.'
        }
        elseif ($deviceBased) {
            Add-Result $cat 'Compliant device requirement' 'WARN' "$detail (report-only)" 'Would block enrollment if enabled.'
        }
        else { Add-Result $cat 'Policy in scope' 'INFO' $detail }
    }
    if (-not $found) { Add-Result $cat 'CA policies' 'PASS' 'No active policy targets Intune enrollment or device join in this context' }
}
#endregion

#region 4. Autopilot device preparation policies
Write-Section '4. Autopilot device preparation policies'
$dppPolicies = [System.Collections.Generic.List[object]]::new()
$AllApps = @{}      # appId    -> policy names
$AllScripts = @{}   # scriptId -> policy names
$UserPolicies = [System.Collections.Generic.List[string]]::new()

$r = Get-Graph -Uri "$Graph/beta/deviceManagement/configurationPolicies" -Category 'DPP policy' -Check 'Reading configurationPolicies'
if ($r.Ok) {
    $cands = @(@($r.Data) | Where-Object {
            $_.templateReference.templateFamily -eq 'enrollmentConfiguration' -or ((@($_.technologies) -join ',') -match 'enrollment')
        })
    if ($PolicyName) { $cands = @($cands | Where-Object { $_.name -like $PolicyName }) }

    foreach ($p in $cands) {
        $s = Get-Graph -Uri "$Graph/beta/deviceManagement/configurationPolicies/$($p.id)/settings" -Category 'DPP policy' -Check "Settings of '$($p.name)'"
        if (-not $s.Ok) { continue }
        $map = @{}
        foreach ($set in @($s.Data)) { Get-SettingValues -Instance $set.settingInstance -Map $map }
        if (@($map.Keys | Where-Object { $_ -like 'enrollment_autopilot_dpp*' }).Count -gt 0) {
            $dppPolicies.Add([pscustomobject]@{ Policy = $p; Settings = $map })
        }
    }

    if ($dppPolicies.Count -eq 0) {
        $f = if ($PolicyName) { " matching '$PolicyName'" } else { '' }
        Add-Result 'DPP policy' 'Presence' 'FAIL' "No Autopilot device preparation policy found$f." `
            'Intune > Devices > Windows > Enrollment > Autopilot device preparation: create a policy.'
    }
}

foreach ($d in $dppPolicies) {
    $p = $d.Policy; $map = $d.Settings
    $cat = "Policy: $($p.name)"
    Add-Result $cat 'Identity' 'INFO' ("id {0}, last modified {1}" -f $p.id, $p.lastModifiedDateTime)

    foreach ($k in ($map.Keys | Sort-Object)) {
        if ($k -match 'allowedappids|allowedscriptids') { continue }
        $label = if ($SettingLabels.ContainsKey($k)) { $SettingLabels[$k] } else { $k }
        $vals = foreach ($v in $map[$k]) {
            $short = $v -replace '^enrollment_autopilot_dpp_', ''
            if ($ChoiceLabels.ContainsKey($v)) { "$short ($($ChoiceLabels[$v]))" } else { $short }
        }
        $txt = ($vals -join ', ')
        if ($txt.Length -gt 150) { $txt = $txt.Substring(0, 150) + '...' }
        Add-Result $cat $label 'INFO' $txt
    }

    # Allowed apps and scripts
    $appIds = Get-Guids -Text @($map.Keys | Where-Object { $_ -match 'allowedappids' } | ForEach-Object { $map[$_] })
    $scriptIds = Get-Guids -Text @($map.Keys | Where-Object { $_ -match 'allowedscriptids' } | ForEach-Object { $map[$_] })
    foreach ($a in $appIds) { if (-not $AllApps.ContainsKey($a)) { $AllApps[$a] = @() }; $AllApps[$a] += $p.name }
    foreach ($s in $scriptIds) { if (-not $AllScripts.ContainsKey($s)) { $AllScripts[$s] = @() }; $AllScripts[$s] += $p.name }

    if ($appIds.Count -gt $Const.MaxApps) {
        Add-Result $cat 'Allowed apps' 'FAIL' "$($appIds.Count) apps (max $($Const.MaxApps))." 'Reduce the list to apps that are critical during OOBE.'
    }
    else { Add-Result $cat 'Allowed apps' 'INFO' "$($appIds.Count) app(s) selected" }
    if ($scriptIds.Count -gt $Const.MaxScripts) {
        Add-Result $cat 'Allowed scripts' 'FAIL' "$($scriptIds.Count) scripts (max $($Const.MaxScripts))." 'Reduce the script list.'
    }
    else { Add-Result $cat 'Allowed scripts' 'INFO' "$($scriptIds.Count) script(s) selected" }

    # Assignments (USER group)
    $a = Get-Graph -Uri "$Graph/beta/deviceManagement/configurationPolicies/$($p.id)/assignments" -Category $cat -Check 'Assignments'
    if ($a.Ok) {
        $asg = @($a.Data)
        if ($asg.Count -eq 0) {
            Add-Result $cat 'Assignments' 'FAIL' 'Policy is not assigned.' 'Assign the policy to a user group.'
        }
        else {
            Add-Result $cat 'Assignments' 'INFO' (Format-Targets -Assignments $asg)
            if ($User) {
                switch (Test-TargetsUser -Assignments $asg -UserGroupIds $UserGroupIds) {
                    'Included' { $UserPolicies.Add($p.name); Add-Result $cat 'User targeting' 'PASS' 'User is targeted by this policy' }
                    'Excluded' { Add-Result $cat 'User targeting' 'WARN' 'User is EXCLUDED from this policy.' 'Review the exclusion groups.' }
                    default { Add-Result $cat 'User targeting' 'INFO' 'User is not targeted by this policy' }
                }
            }
        }
    }
}

if ($User -and $dppPolicies.Count -gt 0) {
    if ($UserPolicies.Count -eq 0) {
        Add-Result 'DPP policy' 'Overall targeting' 'FAIL' 'No DPP policy targets this user: OOBE will finish without device preparation.' `
            'Add the user to the group assigned to the policy (a user group, not a device group).'
    }
    elseif ($UserPolicies.Count -gt 1) {
        Add-Result 'DPP policy' 'Overall targeting' 'WARN' ("Several policies target the user: {0}" -f ($UserPolicies -join ', ')) `
            'Only the highest priority policy applies: check the order in the portal.'
    }
}
#endregion

#region 5. Device group
Write-Section '5. Device group (Enrollment time grouping)'
$cat = 'Device group'
$DevGroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$OwnedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($spProv) {
    $r = Get-Graph -Uri "$Graph/v1.0/servicePrincipals/$($spProv.id)/ownedObjects/microsoft.graph.group?`$select=id,displayName" -Category $cat -Check 'Groups owned by the SP'
    if ($r.Ok) {
        foreach ($g in @($r.Data)) { [void]$OwnedIds.Add(([string]$g.id).Trim()); [void]$DevGroupIds.Add(([string]$g.id).Trim()) }
        Add-Result $cat 'Groups owned by Intune Provisioning Client' 'INFO' ("{0} group(s): {1}" -f $OwnedIds.Count, ((@($r.Data) | ForEach-Object { $_.displayName }) -join ', '))
    }
}
foreach ($id in @($DeviceGroupId)) { if ($id) { [void]$DevGroupIds.Add($id.Trim()) } }

if ($DevGroupIds.Count -eq 0) {
    Add-Result $cat 'Detection' 'FAIL' 'No device group detected (no group owned by Intune Provisioning Client).' `
        'Create an Assigned security group, add "Intune Provisioning Client" (f1346770-...) as OWNER, then select it in the policy.'
}

foreach ($gid in $DevGroupIds) {
    $g = Get-Graph -Uri "$Graph/v1.0/groups/$($gid)?`$select=id,displayName,groupTypes,securityEnabled,mailEnabled,isAssignableToRole,membershipRule" -Category $cat -Check "Group $gid"
    if (-not $g.Ok) { continue }
    $grp = $g.Data
    $gcat = "Group: $($grp.displayName)"

    if (@($grp.groupTypes) -contains 'DynamicMembership') {
        Add-Result $gcat 'Membership type' 'FAIL' "Dynamic group ($($grp.membershipRule))." 'The DPP group must use Assigned membership.'
    }
    else { Add-Result $gcat 'Membership type' 'PASS' 'Assigned' }

    if (-not $grp.securityEnabled) { Add-Result $gcat 'Security group' 'FAIL' 'securityEnabled = false.' 'Use a security group.' }
    if ($grp.isAssignableToRole) { Add-Result $gcat 'Role-assignable' 'WARN' 'Group is assignable to Entra roles.' 'Not recommended for DPP: use a standard security group.' }

    # Ownership: three independent proofs, any one is enough
    #   1. the group appears in the SP ownedObjects (reverse relationship, most reliable)
    #   2. the SP objectId (resolved by appId in THIS tenant) appears in the group owners
    #   3. a service principal owning the group carries the Intune Provisioning Client appId
    $ownCheck = 'Intune Provisioning Client owner'
    $spId = if ($spProv) { ([string]$spProv.id).Trim() } else { '' }
    $evidence = [System.Collections.Generic.List[string]]::new()
    $readOk = $false

    if ($spProv) { $readOk = $true }
    if ($OwnedIds.Contains(([string]$gid).Trim())) { $evidence.Add('SP ownedObjects') }

    $o = Get-Graph -Uri "$Graph/v1.0/groups/$($gid)/owners/microsoft.graph.servicePrincipal?`$select=id,appId,displayName" -Quiet
    if ($o.Ok) {
        $readOk = $true
        foreach ($sp in @($o.Data)) {
            $oid = ([string]$sp.id).Trim()
            if ($spId -and [string]::Equals($oid, $spId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $evidence.Add("owners, objectId $oid")
            }
            elseif ([string]::Equals(([string]$sp.appId).Trim(), $Const.ProvisioningClientAppId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $evidence.Add("owners, appId (objectId $oid)")
            }
        }
    }

    if ($evidence.Count -gt 0) {
        Add-Result $gcat $ownCheck 'PASS' ("Confirmed via: {0}" -f ($evidence -join ' ; '))
    }
    elseif (-not $readOk) {
        Add-Result $gcat $ownCheck 'SKIP' "Owners could not be read: $($o.Error)" 'Check Group.Read.All / Application.Read.All.'
    }
    else {
        # Show the owners actually returned to ease troubleshooting
        $all = Get-Graph -Uri "$Graph/v1.0/groups/$($gid)/owners?`$select=id,displayName" -Quiet
        $list = if ($all.Ok -and @($all.Data).Count -gt 0) {
            (@($all.Data) | ForEach-Object { "{0} [{1}] {2}" -f $_.displayName, (([string]$_.'@odata.type') -replace '#microsoft.graph.', ''), $_.id }) -join ' ; '
        }
        elseif ($all.Ok) { 'none' }
        else { "read failed: $($all.Error)" }
        Add-Result $gcat $ownCheck 'FAIL' ("Expected SP (objectId {0}) is not an owner. Owners returned: {1}" -f $spId, $list) `
            'Entra > Groups > [group] > Owners > Add: "Intune Provisioning Client" (AppId f1346770-5b25-470b-88bd-d5744ab7952c).'
    }

    $m = Get-Graph -Uri "$Graph/v1.0/groups/$($gid)/members?`$select=id&`$top=999" -Quiet
    if ($m.Ok) { Add-Result $gcat 'Members' 'INFO' ("{0} member(s)" -f @($m.Data).Count) }
}
#endregion

#region 6. Allowed apps and scripts
Write-Section '6. Allowed apps and scripts'
$UnsupportedTypes = @('webApp', 'microsoftStoreForBusinessApp', 'windowsStoreApp', 'windowsWebApp')

foreach ($appId in $AllApps.Keys) {
    $cat = 'DPP apps'
    $r = Get-Graph -Uri "$Graph/beta/deviceAppManagement/mobileApps/$($appId)?`$expand=assignments" -Quiet
    if (-not $r.Ok) {
        Add-Result $cat "App $appId" 'FAIL' "Not found or not accessible ($($r.Error)). Referenced by: $($AllApps[$appId] -join ', ')" `
            'App deleted? Remove it and select it again in the policy.'
        continue
    }
    $app = $r.Data
    $type = ([string]$app.'@odata.type') -replace '#microsoft.graph.', ''
    $name = "$($app.displayName) [$type]"

    if ($type -in $UnsupportedTypes) {
        Add-Result $cat $name 'WARN' 'App type probably not supported by device preparation.' 'Use Win32, MSI LOB, WinGet (new Store) or Microsoft 365 Apps.'
    }
    if ($app.publishingState -and $app.publishingState -ne 'published') {
        Add-Result $cat $name 'WARN' "publishingState = $($app.publishingState)" 'Content not published (upload in progress or failed): wait or upload again.'
    }
    if ($type -eq 'win32LobApp' -and $app.installExperience.runAsAccount -eq 'user') {
        Add-Result $cat $name 'WARN' 'Install context: user.' 'During OOBE, prefer the System context.'
    }

    if ($DevGroupIds.Count -eq 0) {
        Add-Result $cat $name 'SKIP' 'Device group unknown: assignment cannot be verified.'
        continue
    }
    $req = @(@($app.assignments) | Where-Object {
            $_.intent -eq 'required' -and
            $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and
            $DevGroupIds.Contains([string]$_.target.groupId)
        })
    if ($req.Count -gt 0) {
        Add-Result $cat $name 'PASS' ("Required on {0}" -f (($req | ForEach-Object { Get-GroupName -Id $_.target.groupId }) -join ', '))
    }
    else {
        $other = Format-Targets -Assignments $app.assignments
        Add-Result $cat $name 'FAIL' "No Required assignment to the device group. Current: $other" `
            'Assign the app as Required to the DPP device group (not to the user group).'
    }
}
if ($AllApps.Count -eq 0 -and $dppPolicies.Count -gt 0) { Add-Result 'DPP apps' 'Apps' 'INFO' 'No app selected in the policies' }

foreach ($sid in $AllScripts.Keys) {
    $cat = 'DPP scripts'
    $r = Get-Graph -Uri "$Graph/beta/deviceManagement/deviceManagementScripts/$($sid)" -Quiet
    if (-not $r.Ok) {
        Add-Result $cat "Script $sid" 'FAIL' "Not found or not accessible ($($r.Error))." 'Remove it and select it again in the policy.'
        continue
    }
    $scr = $r.Data
    $name = "$($scr.displayName)"
    if ($scr.runAsAccount -eq 'user') {
        Add-Result $cat $name 'WARN' 'Runs in the user context.' 'During OOBE, prefer the System context.'
    }
    if ($DevGroupIds.Count -eq 0) { Add-Result $cat $name 'SKIP' 'Device group unknown.'; continue }

    $a = Get-Graph -Uri "$Graph/beta/deviceManagement/deviceManagementScripts/$($sid)/assignments" -Quiet
    $hit = @(@($a.Data) | Where-Object { $_.target.groupId -and $DevGroupIds.Contains([string]$_.target.groupId) -and $_.target.'@odata.type' -ne '#microsoft.graph.exclusionGroupAssignmentTarget' })
    if ($hit.Count -gt 0) { Add-Result $cat $name 'PASS' 'Assigned to the device group' }
    else {
        Add-Result $cat $name 'FAIL' ("Not assigned to the device group. Current: {0}" -f (Format-Targets -Assignments $a.Data)) `
            'Assign the script to the DPP device group.'
    }
}
#endregion

#region 7. Device
if ($SerialNumber) {
    Write-Section "7. Device: $SerialNumber"
    $cat = 'Device'
    $sn = $SerialNumber.Replace("'", "''")

    # 7.1 Autopilot v1 conflict
    $r = Get-Graph -Uri "$Graph/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$sn')" -Category $cat -Check 'Autopilot v1 registration'
    if ($r.Ok) {
        $ap = @($r.Data)
        if ($ap.Count -eq 0) {
            Add-Result $cat 'Autopilot v1 registration' 'PASS' 'Hash not registered: no conflict with a v1 profile'
        }
        foreach ($x in $ap) {
            $st = [string]$x.deploymentProfileAssignmentStatus
            if ($st -match '^assigned') {
                Add-Result $cat 'Autopilot v1 registration' 'FAIL' "Registered in v1 (groupTag '$($x.groupTag)', profile: $st). The v1 profile takes precedence over device preparation." `
                    'Delete the registration (Devices > Windows > Enrollment > Devices) if the device must go through DPP.'
            }
            else {
                Add-Result $cat 'Autopilot v1 registration' 'WARN' "Registered in v1 without an effective profile (status: $st, groupTag '$($x.groupTag)')." `
                    'A leftover v1 registration can interfere: delete it if the device must go through DPP.'
            }
        }
    }

    # 7.2 Corporate identifier
    if ($personalBlocked) {
        $r = Get-Graph -Uri "$Graph/beta/deviceManagement/importedDeviceIdentities" -Category $cat -Check 'Corporate identifier'
        if ($r.Ok) {
            $hit = @(@($r.Data) | Where-Object { $_.importedDeviceIdentifier -like "*$SerialNumber*" })
            if ($hit.Count -gt 0) { Add-Result $cat 'Corporate identifier' 'PASS' $hit[0].importedDeviceIdentifier }
            else {
                Add-Result $cat 'Corporate identifier' 'FAIL' 'Personal enrollment is blocked and no corporate identifier exists for this serial number: enrollment will be refused.' `
                    'Intune > Devices > Enrollment > Corporate device identifiers: import "Manufacturer,Model,SerialNumber".'
            }
        }
    }

    # 7.3 Intune object
    $r = Get-Graph -Uri "$Graph/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$sn'" -Category $cat -Check 'Intune object'
    $mds = if ($r.Ok) { @($r.Data) } else { @() }
    if ($r.Ok -and $mds.Count -eq 0) {
        Add-Result $cat 'Intune object' 'INFO' 'No Intune object: MDM enrollment did not complete (or the object was deleted).'
    }
    if ($mds.Count -gt 1) {
        Add-Result $cat 'Intune object' 'WARN' "$($mds.Count) Intune objects for this serial number." 'Clean up stale objects (Intune and Entra).'
    }

    foreach ($md in $mds) {
        Add-Result $cat 'Intune object' 'INFO' ("{0} | enrolled {1} | last sync {2} | UPN {3}" -f $md.deviceName, $md.enrolledDateTime, $md.lastSyncDateTime, $md.userPrincipalName)
        Add-Result $cat 'Enrollment' 'INFO' ("type {0} | join {1} | ownership {2} | compliance {3}" -f $md.deviceEnrollmentType, $md.joinType, $md.managedDeviceOwnerType, $md.complianceState)

        if ($md.managedDeviceOwnerType -eq 'personal') {
            Add-Result $cat 'Ownership' 'WARN' 'Device marked as Personal.' 'A DPP device should be Corporate: check corporate identifiers.'
        }
        if ($UserPrincipalName -and $md.userPrincipalName -and ($md.userPrincipalName -ne $UserPrincipalName)) {
            Add-Result $cat 'Primary user' 'INFO' "Different from the tested UPN: $($md.userPrincipalName)"
        }

        $ver = $null
        try { $ver = [version]$md.osVersion } catch { }
        if ($ver) {
            if ($ver.Build -lt $Const.MinBuild) {
                Add-Result $cat 'Windows version' 'FAIL' "$($md.osVersion): DPP requires Windows 11 22H2 (with KB5035942) or later." 'Use a recent Windows 11 media.'
            }
            elseif (($ver.Build -in 22621, 22631) -and $ver.Revision -lt $Const.MinUbr2262x) {
                Add-Result $cat 'Windows version' 'WARN' "$($md.osVersion) is older than KB5035942." 'Update the installation image.'
            }
            else { Add-Result $cat 'Windows version' 'PASS' $md.osVersion }
        }

        # 7.4 Entra object and device group membership
        if ($md.azureADDeviceId -and $md.azureADDeviceId -ne '00000000-0000-0000-0000-000000000000') {
            $e = Get-Graph -Uri "$Graph/v1.0/devices?`$filter=deviceId eq '$($md.azureADDeviceId)'" -Category $cat -Check 'Entra object'
            $ed = if ($e.Ok) { @($e.Data) | Select-Object -First 1 } else { $null }
            if ($e.Ok -and -not $ed) {
                Add-Result $cat 'Entra object' 'FAIL' "No Entra object for deviceId $($md.azureADDeviceId)." 'Object deleted or out of sync: reset the device after cleanup.'
            }
            elseif ($ed) {
                switch ($ed.trustType) {
                    'AzureAd' { Add-Result $cat 'Entra join type' 'PASS' 'Microsoft Entra joined' }
                    'ServerAd' { Add-Result $cat 'Entra join type' 'FAIL' 'Hybrid joined: not supported by device preparation.' 'Use Autopilot v1 for hybrid, or move to Entra join.' }
                    'Workplace' { Add-Result $cat 'Entra join type' 'WARN' 'Only registered (Workplace), not joined.' 'Check the OOBE flow: a work account is required.' }
                    default { Add-Result $cat 'Entra join type' 'INFO' "trustType = $($ed.trustType)" }
                }
                if (-not $ed.accountEnabled) { Add-Result $cat 'Entra object' 'FAIL' 'Device disabled in Entra.' 'Re-enable the device.' }

                if ($DevGroupIds.Count -eq 0) {
                    Add-Result $cat 'Device group' 'SKIP' 'Device group unknown.'
                }
                else {
                    $mo = Get-Graph -Uri "$Graph/v1.0/devices/$($ed.id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName" -Category $cat -Check 'Group membership'
                    if ($mo.Ok) {
                        $in = @(@($mo.Data) | Where-Object { $DevGroupIds.Contains([string]$_.id) })
                        if ($in.Count -gt 0) {
                            Add-Result $cat 'Device group' 'PASS' ("Member of: {0}" -f (($in | ForEach-Object { $_.displayName }) -join ', '))
                        }
                        else {
                            Add-Result $cat 'Device group' 'FAIL' 'The device was not added to any DPP device group: apps and scripts will not install during OOBE.' `
                                'Typical causes: Intune Provisioning Client not owner of the group, group not selected in the policy, or DPP policy not applied (v1 profile took precedence).'
                        }
                    }
                }
            }
        }
    }
}
else {
    Write-Section '7. Device'
    Add-Result 'Device' 'Device checks' 'SKIP' '-SerialNumber parameter not provided.'
}
#endregion

#region 8. Enrollment failure events
if ($User) {
    Write-Section ("8. Intune enrollment failures (last {0} days)" -f $LookbackDays)
    $cat = 'Events'
    $r = Get-Graph -Uri "$Graph/beta/deviceManagement/troubleshootingEvents" -Category $cat -Check 'troubleshootingEvents'
    if ($r.Ok) {
        $since = (Get-Date).AddDays(-$LookbackDays)
        $ev = @(@($r.Data) | Where-Object {
                $_.userId -eq $User.id -and $_.eventDateTime -and ([datetime]$_.eventDateTime) -ge $since
            } | Sort-Object { [datetime]$_.eventDateTime } -Descending)
        if ($ev.Count -eq 0) { Add-Result $cat 'Enrollment failures' 'PASS' 'No failure recorded for this user' }
        foreach ($x in ($ev | Select-Object -First 15)) {
            Add-Result $cat 'Enrollment failure' 'WARN' ("{0} | {1} | {2} | OS {3}" -f $x.eventDateTime, $x.failureCategory, $x.failureReason, $x.osVersion) `
                'Correlate with client-side logs (MDMDiagnosticsTool, Event Viewer).'
        }
        if ($ev.Count -gt 15) { Add-Result $cat 'Enrollment failures' 'INFO' "$($ev.Count) events in total, 15 shown." }
    }
}
#endregion

#region Summary
Write-Section 'Summary'
$count = @{}
foreach ($s in 'PASS', 'WARN', 'FAIL', 'INFO', 'SKIP') { $count[$s] = @($script:Results | Where-Object Status -eq $s).Count }
Write-Host ("  PASS {0} | WARN {1} | FAIL {2} | INFO {3} | SKIP {4}" -f $count.PASS, $count.WARN, $count.FAIL, $count.INFO, $count.SKIP) -ForegroundColor White

$issues = @($script:Results | Where-Object { $_.Status -in 'FAIL', 'WARN' } | Sort-Object @{ e = { if ($_.Status -eq 'FAIL') { 0 } else { 1 } } })
if ($issues.Count -gt 0) {
    Write-Host ''
    Write-Host '  Items to address, by severity:' -ForegroundColor White
    $i = 1
    foreach ($x in $issues) {
        $c = if ($x.Status -eq 'FAIL') { 'Red' } else { 'Yellow' }
        Write-Host ("  {0,2}. [{1}] {2} / {3}" -f $i, $x.Status, $x.Category, $x.Check) -ForegroundColor $c
        Write-Host ("      {0}" -f $x.Detail)
        if ($x.Remediation) { Write-Host ("      -> {0}" -f $x.Remediation) -ForegroundColor DarkYellow }
        $i++
    }
}
else {
    Write-Host '  No tenant-side issue detected. Next step: client-side logs.' -ForegroundColor Green
}

if ($ExportPath) {
    if (-not (Test-Path -Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $csvPath = Join-Path $ExportPath "AutopilotDPP-Diag-$stamp.csv"
    $htmlPath = Join-Path $ExportPath "AutopilotDPP-Diag-$stamp.html"

    $view = $script:Results | Select-Object Status, Category, Check, Detail, Remediation

    $view | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    $frag = $view | ConvertTo-Html -Fragment
    foreach ($s in 'PASS', 'WARN', 'FAIL', 'INFO', 'SKIP') {
        $frag = $frag -replace "<td>$s</td>", "<td class=`"s-$($s.ToLower())`">$s</td>"
    }
    $css = @'
<style>
:root { color-scheme: light dark; --bg:#ffffff; --fg:#1b1b1b; --line:#d0d0d0; --head:#f0f2f5; }
@media (prefers-color-scheme: dark) { :root { --bg:#1e1e1e; --fg:#e6e6e6; --line:#3a3a3a; --head:#2a2d31; } }
body { font-family: Segoe UI, Arial, sans-serif; background: var(--bg); color: var(--fg); margin: 24px; }
h1 { font-size: 20px; } p { color: #888; }
table { border-collapse: collapse; width: 100%; font-size: 13px; }
th, td { border: 1px solid var(--line); padding: 6px 8px; text-align: left; vertical-align: top; }
th { background: var(--head); }
.s-pass { background:#1e7e34; color:#fff; font-weight:600; } .s-fail { background:#c82333; color:#fff; font-weight:600; }
.s-warn { background:#e0a800; color:#000; font-weight:600; } .s-info { background:#17a2b8; color:#fff; } .s-skip { background:#6c757d; color:#fff; }
</style>
'@
    $summary = "PASS {0} | WARN {1} | FAIL {2} | INFO {3} | SKIP {4}" -f $count.PASS, $count.WARN, $count.FAIL, $count.INFO, $count.SKIP
    $ctxLine = "User: {0} | Serial number: {1} | Generated on {2}" -f ($(if ($UserPrincipalName) { $UserPrincipalName } else { 'n/a' })), ($(if ($SerialNumber) { $SerialNumber } else { 'n/a' })), (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $doc = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Autopilot device preparation diagnostic</title>$css</head><body><h1>Autopilot device preparation diagnostic</h1><p>$ctxLine<br>$summary</p>$($frag -join "`n")</body></html>"
    Set-Content -Path $htmlPath -Value $doc -Encoding UTF8

    Write-Host ''
    Write-Host "  HTML report: $htmlPath" -ForegroundColor Cyan
    Write-Host "  CSV report : $csvPath" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '  Graph session kept open. To close it: Disconnect-MgGraph' -ForegroundColor DarkGray

if ($PassThru) { $script:Results }
#endregion
