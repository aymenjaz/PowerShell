$processes = Get-Process -errorAction SilentlyContinue | where { ( $_.ProcessName -ne "powershell" ) -and ( $_.SessionId -eq ([System.Diagnostics.Process]::GetCurrentProcess().SessionId) ) }

ForEach ( $proc in $processes ) 
{
		if ( -not ($proc.MainWindowHandle -and $proc.Responding) ) 
        {   
				$proc.kill()
		}
}
