
$Directoryscan = 'C:\Temp\'
$OUTFileName = 'C:\Reports\DOCS_Scan.csv'
# Specify number of days back
$DayBack = 15

#we can include or exclude some file extension (-include *.log  -exclude *.mp4)
Get-ChildItem -Path $Directoryscan -Recurse | 

Select-Object Name , @{label = 'Size (MB)'; expression = {$_.Length/ 1mB -as [int]}}, LastWriteTime , FullName  | Sort-Object -Descending 'Size (MB)' |

Where-Object { ($_.LastWriteTime -gt (Get-Date).AddDays(-$DayBack)) }  | Export-Csv $OUTFileName -Delimiter ';' -Encoding UTF8 -Force
