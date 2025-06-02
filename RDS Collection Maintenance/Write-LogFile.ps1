
#=============================== 1- LOG Function =====================================
$Output_Dir = 'C:\Report\'

function Write-LogFile 
{
	[CmdletBinding()]
	param(
		[Parameter()]
		[string] $Message
	)
	
    if((Test-Path $Output_Dir) -eq $false)
    {
        New-Item -ItemType Directory -Path $Output_Dir
    }
    $date = Get-Date
    $Message + ' ; ' + $date | Out-File "$($Output_Dir)RDSLog_$(Get-Date -Format "dd-MM-yyyy")).txt" -Append
}
