
# 🧾 Azure PowerShell Cheat Sheet (Az Module 7.2+)

> For use with [Az PowerShell Module](https://learn.microsoft.com/en-us/powershell/azure/?view=azps-8.3.0)

## 🧰 Setup & Authentication

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned

# Install Az module if not already available
IF (-not (Get-Module -Name Az -ListAvailable)) {
    Install-Module -Name Az -Force -AllowClobber
}

# Import Az module
Import-Module Az

# Connect to Azure
Connect-AzAccount
```

---

## 💻 Virtual Machines (VM)

```powershell
# Create a Resource Group
New-AzResourceGroup -Name TutorialResources -Location eastus

# Credentials for VM
$cred = Get-Credential -Message "Enter a username and password for the virtual machine."

# Create VM
$vmParams = @{
    ResourceGroupName = 'TutorialResources'
    Name              = 'TutorialVM1'
    Location          = 'eastus'
    ImageName         = 'Win2016Datacenter'
    PublicIpAddressName = 'tutorialPublicIp'
    Credential        = $cred
    OpenPorts         = 3389
    Size              = 'Standard_D2s_v3'
}
$newVM1 = New-AzVM @vmParams
```

### 🕵️ VM Info

```powershell
# OS info
$newVM1.OSProfile | Select-Object ComputerName, AdminUserName

# Network config
$newVM1 | Get-AzNetworkInterface | Select-Object -ExpandProperty IpConfigurations | Select-Object Name, PrivateIpAddress

# Public IP
$publicIp = Get-AzPublicIpAddress -Name tutorialPublicIp -ResourceGroupName TutorialResources
$publicIp | Select-Object Name, IpAddress, @{label='FQDN';expression={$_.DnsSettings.Fqdn}}

# Connect to VM (RDP)
mstsc.exe /v $publicIp.IpAddress
```

---

## 💻 Create Another VM in Same Subnet

```powershell
$vm2Params = @{
    ResourceGroupName     = 'TutorialResources'
    Name                  = 'TutorialVM2'
    ImageName             = 'Win2016Datacenter'
    VirtualNetworkName    = 'TutorialVM1'
    SubnetName            = 'TutorialVM1'
    PublicIpAddressName   = 'tutorialPublicIp2'
    Credential            = $cred
    OpenPorts             = 3389
}
$newVM2 = New-AzVM @vm2Params

# Connect with DNS
mstsc.exe /v $newVM2.FullyQualifiedDomainName
```

---

## 🌐 Virtual Network

```powershell
# Create VNet Resource Group
New-AzResourceGroup -Name 'CreateVNetQS-rg' -Location 'EastUS'

# Create VNet
$vnet = @{
    Name              = 'myVNet'
    ResourceGroupName = 'CreateVNetQS-rg'
    Location          = 'EastUS'
    AddressPrefix     = '10.0.0.0/16'
}
$virtualNetwork = New-AzVirtualNetwork @vnet

# Add Subnet
$subnet = @{
    Name            = 'default'
    VirtualNetwork  = $virtualNetwork
    AddressPrefix   = '10.0.0.0/24'
}
Add-AzVirtualNetworkSubnetConfig @subnet
$virtualNetwork | Set-AzVirtualNetwork
```

---

## 💻 VMs in VNet

```powershell
# VM1 in VNet
$vm1 = @{
    ResourceGroupName   = 'CreateVNetQS-rg'
    Location            = 'EastUS'
    Name                = 'myVM1'
    VirtualNetworkName  = 'myVNet'
    SubnetName          = 'default'
}
New-AzVM @vm1 -AsJob

# VM2 in VNet
$vm2 = @{
    ResourceGroupName   = 'CreateVNetQS-rg'
    Location            = 'EastUS'
    Name                = 'myVM2'
    VirtualNetworkName  = 'myVNet'
    SubnetName          = 'default'
}
New-AzVM @vm2
```

### 🔗 Connect via Public IP

```powershell
$ip = @{
    Name              = 'myVM1'
    ResourceGroupName = 'CreateVNetQS-rg'
}
Get-AzPublicIpAddress @ip | Select-Object IpAddress
mstsc /v (Get-AzPublicIpAddress @ip | Select-Object -ExpandProperty IpAddress)
```

---

## 🔄 Allow Ping Between VMs

```powershell
# Run inside both VMs
New-NetFirewallRule –DisplayName "Allow ICMPv4-In" –Protocol ICMPv4
```

---

## 🗄️ Storage Account

```powershell
# Create Resource Group for Storage
New-AzResourceGroup -Name 'Storage-rg' -Location 'EastUS'

# Create Storage Account (RA-GRS, must be lowercase & globally unique)
New-AzStorageAccount -ResourceGroupName 'Storage-rg' `
    -Name "accountname12457" `
    -Location 'EastUS' `
    -SkuName Standard_RAGRS `
    -Kind StorageV2
```

---

## 🌐 Storage with DNS Zone Endpoints (Preview)

```powershell
# Prerequisites
Install-Module PowerShellGet -Repository PSGallery -Force
Install-Module Az.Storage -Repository PSGallery -RequiredVersion 4.4.2-preview -AllowClobber -AllowPrerelease -Force

# Create Storage Account with DNS Endpoint
$account = New-AzStorageAccount -ResourceGroupName "resource-group" `
    -Name "storage-account" `
    -SkuName Standard_RAGRS `
    -Location "location" `
    -Kind StorageV2 `
    -DnsEndpointType AzureDnsZone

# Get endpoints
$account.PrimaryEndpoints
$account.SecondaryEndpoints
```

---

## 🧹 Cleanup & Logout

```powershell
# Delete Storage Account
Remove-AzStorageAccount -Name "storage-account" -ResourceGroupName "resource-group"

# Delete entire Resource Group
$job = Remove-AzResourceGroup -Name TutorialResources -Force -AsJob
Wait-Job -Id $job.Id

# Disconnect from Azure
Disconnect-AzAccount
```

---

