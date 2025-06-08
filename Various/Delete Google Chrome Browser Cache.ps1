
$username = $env:USERNAME

Remove-Item "c:\users\$username\appdata\local\google\chrome\user data\default\cache\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "c:\users\$username\appdata\local\google\chrome\user data\default\code cache\js\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "c:\users\$username\appdata\local\google\chrome\user data\default\media cache\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "c:\users\$username\appdata\local\google\chrome\user data\Default\Service Worker\CacheStorage\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "c:\users\$username\appdata\local\google\chrome\user data\Default\Service Worker\ScriptCache\*" -Recurse -Force -ErrorAction SilentlyContinue
