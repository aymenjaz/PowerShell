# ============================================================================================
# 1. Configure PowerShell Execution Policy
# ============================================================================================
# Allow execution of local scripts signed by a trusted publisher.
Set-ExecutionPolicy RemoteSigned -Force

# ============================================================================================
# 2. Import Exchange Online Module
# ============================================================================================
# Load the ExchangeOnlineManagement module (must be installed beforehand).
Import-Module ExchangeOnlineManagement

# ============================================================================================
# 3. Connect to Exchange Online
# ============================================================================================
Write-Host "Connect to Exchange Online" -ForegroundColor Cyan
Connect-ExchangeOnline

# ============================================================================================
# 4. Enable External Email Tagging
# ============================================================================================
# Activate external tagging feature in Outlook (adds "External" label on emails from outside the org).
Set-ExternalInOutlook -Enabled $true

# Verify external tagging status
Get-ExternalInOutlook

# ============================================================================================
# 5. Add Trusted Domains to External Tagging Allow List
# ============================================================================================
# Emails from domains on this list will NOT be marked as external.
Set-ExternalInOutlook -AllowList @{Add="GlobalITNow.com"}

# ============================================================================================
# 6. Define HTML Disclaimer for Suspicious External Emails
# ============================================================================================
# This block defines a yellow warning banner displayed on emails matching phishing patterns.
$HTMLDisclaimer = '<table border=0 cellspacing=0 cellpadding=0 align="left" width="100%">
  <tr>
    <td style="background:#ffb900;padding:5pt 2pt 5pt 2pt"></td>
    <td width="100%" cellpadding="7px 6px 7px 15px" style="background:yellow;padding:5pt 4pt 5pt 12pt;word-wrap:break-word">
      <div style="color:#222222;">
        <h2><span style="color:#222; font-weight:bold;"><p style="color:red;">Caution:</p></span></h2>
        <b>This is an external email and has a suspicious subject or content. Please take care when clicking links or opening attachments. When in doubt, contact your IT Department.</b> <br><br>
      </div>
    </td>
  </tr>
</table>
<br/>
<br>'

# ============================================================================================
# 7. Define Common Phishing Keywords
# ============================================================================================
# These patterns are used to identify emails containing suspicious or phishing content.
$PhishingKeys = "Password.*[expire|reset]","Password access","[reset|change|update].*password","Change.*password","\.odt","E-Notification",
"EMERGENCY","Retrieve*.document","Download*.document","confirm ownership for","word must be installed","prevent further unauthorized",
"prevent further unauthorised","informations has been","fallow our process","confirm your informations","failed to validate","unable to verify",
"delayed payment","activate your account","Update your payment","submit your payment","via Paypal","has been compromised","FRAUD NOTICE",
"your account will be closed","your apple id was used to sign in to","was blocked for violation","urged to download","that you validate your account",
"multiple login attempt","trying to access your account","suspend your account","restricted if you fail to update","informations on your account",
"update your account information","update in our security","Unusual sign-in activity","Account Was Limited","verify and reactivate","has.*been.*limited",
"have.*locked","has.*been.*suspended","unusual.*activity","notifications.*pending","your\ (customer\ )?account\ has","your\ (customer\ )?account\ was",
"new.*voice(\ )?mail","Periodic.*Maintenance","refund.*not.*approved","account.*(is\ )?on.*hold","wire.*transfer","secure.*update","secure.*document",
"temporar(il)?y.*deactivated","verification.*required","blocked\ your?\ online","suspicious\ activit","securely*.onedrive","securely*.dropbox",
"securely*.google drive","view message","view attachment"

# ============================================================================================
# 8. Create Mail Flow (Transport) Rule
# ============================================================================================
Write-Host "Creating Transport Rule" -ForegroundColor Cyan

New-TransportRule -Name "External Email Warning" `
                  -FromScope NotInOrganization `
                  -SentToScope InOrganization `
                  -SubjectOrBodyMatchesPatterns $PhishingKeys `
                  -ApplyHtmlDisclaimerLocation Prepend `
                  -ApplyHtmlDisclaimerText $HTMLDisclaimer `
                  -ApplyHtmlDisclaimerFallbackAction Wrap

Write-Host "Transport rule created" -ForegroundColor Green
