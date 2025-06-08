

# Mapp Network Drive

$Credentials = Get-Credential

New-PSDrive -Name O -PSProvider "FileSystem" -Root "\\10.0.0.150\homes" -Persist  -Credential $Credentials

