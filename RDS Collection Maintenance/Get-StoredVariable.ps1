
#======================== 3- Function to retrive stored variable from file ================
function Get-StoredVariable
{
	[CmdletBinding()]
	param(
        [Parameter(Mandatory = $false)]
		[string] $Output_Dir = "C:\Report\",

        [Parameter(Mandatory = $false)]
		[string] $File_Name = "Stored_Variable.xml"
	)
	
    if((Test-Path $Output_Dir))
    {
        #To get stored variable in the file :
        return import-clixml -path $Output_Dir$File_Name
    }
    else
    {
        Write-Host "Error : cant Find the Variable in default location : C:\Report\Stored_Variable.xml " -ForegroundColor Red
    }
}

# test Function Store-Variable 
# Get-StoredVariable

