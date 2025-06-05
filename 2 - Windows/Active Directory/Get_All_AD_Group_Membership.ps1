Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

Import-Module ActiveDirectory

# Get the Documents folder path
$DocumentsPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"

# Create the full output path
$OutFilePath = $DocumentsPath + "\Group_Membership.txt"

# Initiate output file
" " | Out-File $OutFilePath  -Force 

$ADGroups = Get-ADGroup -Filter * 

foreach($Group in $ADGroups)
{
    $Members = Get-ADGroupMember  -Identity $Group.Name | Select-Object name , @{Label = 'User Name' ; e= {$_.SamAccountName} }, objectClass  | Sort-Object Name
    if($null -ne $Members )
    {
        "=========================" + $Group.Name + "=========================" | Out-File $OutFilePath -Append -Force 
       
        $Members | Out-File $OutFilePath -Append -Force 
    }
} 
