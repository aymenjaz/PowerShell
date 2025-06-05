
$userName = 'jean.claude.vandam@gmail.com'
$userPassword = '123456789'

# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)


$mailParams = @{
    smtpServer                  = "smtp.gmail.com"
    Port                        = 587
    UseSSL                      = $false
    Credential                  = $credObject
    From                        = $userName
    To                          = "user1@gmail.com"
    Subject                     = "Email de test"
    Body                        = "Message SMTP test"
    DeliveryNotificationOption  = 'onFailure','OnSuccess'
}

Send-MailMessage @mailParams 
