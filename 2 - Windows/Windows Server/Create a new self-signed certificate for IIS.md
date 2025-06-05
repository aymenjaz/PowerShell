
## 🔐 Self-Signed Certificate for IIS Express – PowerShell Cheat Sheet

### 📌 Create a Self-Signed Certificate

```powershell
$certificate = New-SelfSignedCertificate `
    -Subject "localhost" `
    -DnsName "localhost" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotBefore (Get-Date) `
    -NotAfter (Get-Date).AddYears(5) `
    -CertStoreLocation "cert:CurrentUser\My" `
    -FriendlyName "IIS Express Development Certificate" `
    -HashAlgorithm SHA256 `
    -KeyUsage DigitalSignature, KeyEncipherment, DataEncipherment `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")
```

### 📁 Export Certificate as `.pfx` and `.cer`

```powershell
$certificatePath = 'Cert:\CurrentUser\My\' + $certificate.ThumbPrint
$pfxPassword = ConvertTo-SecureString ([Guid]::NewGuid().ToString()) -AsPlainText -Force
$pfxFilePath = [System.IO.Path]::GetTempFileName()
$cerFilePath = [System.IO.Path]::GetTempFileName()

Export-PfxCertificate -Cert $certificatePath -FilePath $pfxFilePath -Password $pfxPassword
Export-Certificate -Cert $certificatePath -FilePath $cerFilePath
```

### ❌ Remove from User Store

```powershell
Remove-Item $certificatePath
```

### ➕ Import to Local Machine & Trust Store

```powershell
# For netsh binding
Import-PfxCertificate -FilePath $pfxFilePath Cert:\LocalMachine\My -Password $pfxPassword -Exportable

# For local trust
Import-Certificate -FilePath $cerFilePath -CertStoreLocation Cert:\CurrentUser\Root
```

### 🔗 Bind Certificate to Ports 44300–44399

```powershell
for ($port = 44300; $port -lt 44400; $port++) {
    "http delete sslcert ipport=0.0.0.0:$port" | netsh
    "http add sslcert ipport=0.0.0.0:$port certhash=$($certificate.Thumbprint) appid=`"{214124cd-d05b-4309-9af9-9caa44b2b74a}`"" | netsh
}
```

### 🧹 Cleanup Temporary Files

```powershell
Remove-Item $pfxFilePath
Remove-Item $cerFilePath
```


