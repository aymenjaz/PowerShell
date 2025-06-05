# Fetches and deletes all temp files & folders 
$tempfolders = @("C:\Windows\Temp\*", "C:\Windows\Prefetch\*", "C:\Documents and Settings\*\Local Settings\temp\*", "C:\Users\*\Appdata\Local\Temp\*", "C:\temp\*")
Remove-Item $tempfolders -force -recurse -ErrorAction SilentlyContinue
