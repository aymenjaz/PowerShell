# Prérequis : Install-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false
$User = "user@domain.com"

# 1. Identité + groupes de sécurité mail-enabled (valeurs nulles exclues)
$me       = Get-Recipient $User
$groups   = Get-Recipient -Filter "Members -eq '$($me.DistinguishedName)'" -RecipientTypeDetails MailUniversalSecurityGroup -ResultSize Unlimited
$trustees = @($me) + @($groups) | Where-Object { $_ }

# 2. Toutes les formes sous lesquelles Exchange peut afficher un trustee
$tn = @{}
foreach ($t in $trustees) {
    foreach ($v in $t.PrimarySmtpAddress, $t.WindowsLiveID, $t.Name, $t.Alias, $t.DisplayName) {
        if ($v) { $tn["$v".ToLower()] = $t.DisplayName }
    }
}

# 3. Boîtes cibles (on exclut la boîte de l'utilisateur lui-même)
$mbx = Get-EXOMailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited |
       Where-Object { $_.ExternalDirectoryObjectId -ne $me.ExternalDirectoryObjectId }
$byName = @{}; $byId = @{}
foreach ($m in $mbx) {
    $byName["$($m.Identity)".ToLower()] = $m; $byName["$($m.Name)".ToLower()] = $m
    $byId[$m.ExternalDirectoryObjectId] = $m
}

$raw = [System.Collections.Generic.List[object]]::new()

# 4. FullAccess : explicite, Allow, non hérité, trustee vérifié
foreach ($m in $mbx) {
    Get-EXOMailboxPermission -Identity $m.PrimarySmtpAddress |
      Where-Object { -not $_.Deny -and -not $_.IsInherited -and $tn.ContainsKey("$($_.User)".ToLower()) } |
      ForEach-Object {
          foreach ($r in (($_.AccessRights -join ',') -split ',\s*')) {
              $raw.Add([pscustomobject]@{ Mbx = $m; Droit = $r; Via = $tn["$($_.User)".ToLower()] })
          }
      }
}

# 5. SendAs
foreach ($t in $trustees) {
    Get-RecipientPermission -Trustee $t.PrimarySmtpAddress -AccessRights SendAs -ResultSize Unlimited |
      Where-Object { $_.AccessControlType -eq 'Allow' -and -not $_.IsInherited -and
                     $tn.ContainsKey("$($_.Trustee)".ToLower()) -and $byName.ContainsKey("$($_.Identity)".ToLower()) } |
      ForEach-Object { $raw.Add([pscustomobject]@{ Mbx = $byName["$($_.Identity)".ToLower()]; Droit = 'SendAs'; Via = $t.DisplayName }) }
}

# 6. SendOnBehalf
foreach ($t in $trustees) {
    Get-Mailbox -Filter "GrantSendOnBehalfTo -eq '$($t.DistinguishedName)'" -ResultSize Unlimited |
      Where-Object { $byId.ContainsKey($_.ExternalDirectoryObjectId) } |
      ForEach-Object { $raw.Add([pscustomobject]@{ Mbx = $byId[$_.ExternalDirectoryObjectId]; Droit = 'SendOnBehalf'; Via = $t.DisplayName }) }
}

# 7. Une ligne par boîte avec tous les droits
$report = $raw | Group-Object { $_.Mbx.ExternalDirectoryObjectId } | ForEach-Object {
    $m = $_.Group[0].Mbx
    [pscustomobject]@{
        Boite  = $m.DisplayName
        Email  = $m.PrimarySmtpAddress
        Type   = $m.RecipientTypeDetails
        Droits = ($_.Group.Droit | Sort-Object -Unique) -join ', '
        Via    = ($_.Group.Via   | Sort-Object -Unique) -join ', '
    }
} | Sort-Object Boite

$report | Format-Table -AutoSize
# $report | Export-Csv ".\Acces_$($User.Split('@')[0]).csv" -NoTypeInformation -Encoding UTF8
