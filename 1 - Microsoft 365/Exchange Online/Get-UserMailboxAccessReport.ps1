<#
.SYNOPSIS
    Lists all mailboxes (user and shared) a given identity can access in Exchange Online.

.DESCRIPTION
    Reverse lookup of mailbox delegations for a user: FullAccess, SendAs and SendOnBehalf,
    including access granted through mail-enabled security groups (one level).
    Only explicit, non-inherited, Allow permissions are reported. One line per mailbox.

.PARAMETER User
    UPN or primary SMTP address of the identity to check.

.EXAMPLE
    .\Get-UserMailboxAccessReport.ps1 -User x@domain.com

.NOTES
    Requires: ExchangeOnlineManagement module, Exchange Recipient Administrator role.
    Nested groups and folder-level permissions are not covered.
#>
param(
    [Parameter(Mandatory)][string]$User
)

Connect-ExchangeOnline -ShowBanner:$false

# 1. Identity + mail-enabled security groups (null values excluded)
$me       = Get-Recipient $User
$groups   = Get-Recipient -Filter "Members -eq '$($me.DistinguishedName)'" -RecipientTypeDetails MailUniversalSecurityGroup -ResultSize Unlimited
$trustees = @($me) + @($groups) | Where-Object { $_ }

# 2. All forms Exchange may use to display a trustee
$tn = @{}
foreach ($t in $trustees) {
    foreach ($v in $t.PrimarySmtpAddress, $t.WindowsLiveID, $t.Name, $t.Alias, $t.DisplayName) {
        if ($v) { $tn["$v".ToLower()] = $t.DisplayName }
    }
}

# 3. Target mailboxes (excluding the user's own mailbox)
$mbx = Get-EXOMailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited |
       Where-Object { $_.ExternalDirectoryObjectId -ne $me.ExternalDirectoryObjectId }
$byName = @{}; $byId = @{}
foreach ($m in $mbx) {
    $byName["$($m.Identity)".ToLower()] = $m; $byName["$($m.Name)".ToLower()] = $m
    $byId[$m.ExternalDirectoryObjectId] = $m
}

$raw = [System.Collections.Generic.List[object]]::new()

# 4. FullAccess: explicit, Allow, non-inherited, trustee verified (one call per mailbox)
foreach ($m in $mbx) {
    Get-EXOMailboxPermission -Identity $m.PrimarySmtpAddress |
      Where-Object { -not $_.Deny -and -not $_.IsInherited -and $tn.ContainsKey("$($_.User)".ToLower()) } |
      ForEach-Object {
          foreach ($r in (($_.AccessRights -join ',') -split ',\s*')) {
              $raw.Add([pscustomobject]@{ Mbx = $m; Right = $r; Via = $tn["$($_.User)".ToLower()] })
          }
      }
}

# 5. SendAs (one server-side call per trustee)
foreach ($t in $trustees) {
    Get-RecipientPermission -Trustee $t.PrimarySmtpAddress -AccessRights SendAs -ResultSize Unlimited |
      Where-Object { $_.AccessControlType -eq 'Allow' -and -not $_.IsInherited -and
                     $tn.ContainsKey("$($_.Trustee)".ToLower()) -and $byName.ContainsKey("$($_.Identity)".ToLower()) } |
      ForEach-Object { $raw.Add([pscustomobject]@{ Mbx = $byName["$($_.Identity)".ToLower()]; Right = 'SendAs'; Via = $t.DisplayName }) }
}

# 6. SendOnBehalf (one server-side call per trustee)
foreach ($t in $trustees) {
    Get-Mailbox -Filter "GrantSendOnBehalfTo -eq '$($t.DistinguishedName)'" -ResultSize Unlimited |
      Where-Object { $byId.ContainsKey($_.ExternalDirectoryObjectId) } |
      ForEach-Object { $raw.Add([pscustomobject]@{ Mbx = $byId[$_.ExternalDirectoryObjectId]; Right = 'SendOnBehalf'; Via = $t.DisplayName }) }
}

# 7. One line per mailbox with all rights
$report = $raw | Group-Object { $_.Mbx.ExternalDirectoryObjectId } | ForEach-Object {
    $m = $_.Group[0].Mbx
    [pscustomobject]@{
        Mailbox = $m.DisplayName
        Email   = $m.PrimarySmtpAddress
        Type    = $m.RecipientTypeDetails
        Rights  = ($_.Group.Right | Sort-Object -Unique) -join ', '
        Via     = ($_.Group.Via   | Sort-Object -Unique) -join ', '
    }
} | Sort-Object Mailbox

$report | Format-Table -AutoSize
# $report | Export-Csv ".\MailboxAccess_$($User.Split('@')[0]).csv" -NoTypeInformation -Encoding UTF8
