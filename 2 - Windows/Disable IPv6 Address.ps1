Get-NetAdapterBinding | Where-Object {($_.Name -EQ 'Ethernet') -and ($_.ComponentID -EQ 'ms_tcpip6')  } 

Disable-NetAdapterBinding -Name 'Ethernet' -ComponentID 'ms_tcpip6'
