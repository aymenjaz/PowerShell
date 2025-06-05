$TempFileLocation = "$env:windir\Temp","$env:TEMP" , "$env:windir\SoftwareDistribution\Download" , "$env:windir\Downloaded Program Files" , "c:\$Recycle.Bin" 
$TempFileCount = ($TempFile).count
$TempFile = Get-ChildItem $TempFileLocation -Recurse -ErrorAction 0 -Force


if($TempFileCount -eq "0") 
{ 
    Write-Host "There are no files in the folder $TempFileLocation" -ForegroundColor Green
}
Else 
{
    $TempFile | Remove-Item -Confirm:$false -Recurse -Force -ErrorAction 0
    Write-Host "Cleared $TempFileCount files in the folder $TempFileLocation" -ForegroundColor Green
}
