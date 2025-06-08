Function Measure-NetworkSpeed{
    # The test file has to be a 10MB file for the math to work. If you want to change sizes, modify the math to match
    $TestFile  = 'https://ftp.sunet.se/mirror/parrotsec.org/parrot/misc/10MB.bin'
    $TempFile  = Join-Path -Path $env:TEMP -ChildPath 'testfile.tmp'
    $WebClient = New-Object Net.WebClient
    $TimeTaken = Measure-Command { $WebClient.DownloadFile($TestFile,$TempFile) } | Select-Object -ExpandProperty TotalSeconds
    $SpeedMbps = (10 / $TimeTaken) * 8
    $Message = "{0:N2} Mbit/sec" -f ($SpeedMbps)
    $Message
}

Measure-NetworkSpeed
