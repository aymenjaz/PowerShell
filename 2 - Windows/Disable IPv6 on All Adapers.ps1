# Disable IPv6 on All Adapers
Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6

# Confirm That all NIC's no longer have IPv6 Enabled
(Get-NetAdapterBinding -Name '*' -ComponentID ms_tcpip6).Enabled
