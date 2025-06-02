# Import Script Write-LogFile
. .\Write-LogFile.ps1

# =========================== 2- Function to store variable in file ===================
# we gonna use this variable ath the end of the first part of script 
# after rebooting the broker to get information about the state of Powershell Script
function Set-StoredVariable
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string] $variable ,

        [Parameter(Mandatory = $false)]
		[string] $Output_Dir = "C:\Report\",

        [Parameter(Mandatory = $false)]
		[string] $File_Name = "Stored_Variable.xml"
	)
	
    if((Test-Path $Output_Dir) -eq $false)
    {
        New-Item -ItemType Directory -Path $Output_Dir
    }
    #To store variable in the file :
    $variable |export-clixml -path $Output_Dir$File_Name
}

# test Function Store-Variable 
# Set-StoredVariable 1

