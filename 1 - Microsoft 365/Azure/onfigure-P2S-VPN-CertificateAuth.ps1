# ==========================================================================================================
# Script Name: Configure-P2S-VPN-CertificateAuth.ps1
# Purpose   : Create and configure Root and Client certificates for Azure VPN Gateway (P2S)
# Auth Type : Certificate-based authentication
# Prerequisites: Run this script on a Windows machine with PowerShell and administrative privileges
# ==========================================================================================================

# ----------------------------------------
# STEP 1: Create a Root Certificate
# ----------------------------------------
# This certificate will be uploaded to Azure to trust client certificates signed by it.
# Note: CN must be descriptive but doesn't need to match any hostname.
$cert = New-SelfSignedCertificate `
    -Type Custom `
    -KeySpec Signature `
    -Subject "CN=Test-VPNGateway-RootCert" `
    -KeyExportPolicy Exportable `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyUsageProperty Sign `
    -KeyUsage CertSign

# ----------------------------------------
# STEP 2: Verify/Create a Reference to the Root Certificate
# ----------------------------------------
# This command lists all certificates in the Personal store. You need to get the Thumbprint of the Root Cert created above.
Get-ChildItem -Path "Cert:\CurrentUser\My"

# Manually replace the Thumbprint value below with the actual one from above output
# This $cert1 object will be used as the signer for the client certificate.
$cert1 = Get-ChildItem -Path "Cert:\CurrentUser\My\9F09F2CDAFD41B739F170CCA4457106FBB56D9FC"

# ----------------------------------------
# STEP 3: Generate a Client Certificate Signed by the Root Certificate
# ----------------------------------------
# This client cert will be installed on client machines that need to connect to the VPN.
# The TextExtension defines it as a client authentication certificate (OID: 1.3.6.1.5.5.7.3.2).
New-SelfSignedCertificate `
    -Type Custom `
    -KeySpec Signature `
    -Subject "CN=Test-VPNGateway-ClientCert" `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(5) `
    -HashAlgorithm sha256 `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Signer $cert1 `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

# ==========================================================================================================
# OUTPUT:
# - Root Certificate: Upload to Azure VPN Gateway under "Point-to-site configuration"
#   Export Public Key: Export-Certificate -Cert $cert -FilePath "C:\VPN-RootCert.cer"
#
# - Client Certificate: Install on client devices that connect via P2S VPN
#   Export PFX: Export-PfxCertificate -Cert $cert1 -FilePath "C:\VPN-ClientCert.pfx" -Password (Read-Host -AsSecureString)
# ==========================================================================================================
