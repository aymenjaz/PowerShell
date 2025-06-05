
# This script is used to block multi instance Application/Process

# Process Name
$processName = "ScreenshotHD"


while($true)
{
    try
    {
        # Get all process with name = process name
        $AllProcess = Get-Process $processName -ErrorAction SilentlyContinue

        if($AllProcess.count -eq 1)
        {
            Write-Host "Only one Application instance is running...." -ForegroundColor Green
        }
        else
        {
            Write-Host "Total of Process Number is : " $AllProcess.count -ForegroundColor Yellow
            
            # Start Killing other process
            $AllProcess | Select-Object -Skip 1 | ForEach-Object {
            Stop-Process -Id $_.Id -Force
            Write-Host "Application Instance Stopped : $($_.Id)"  -ForegroundColor Yellow
            }
        }
    }
    catch
    {
        Write-Host "Error : Please check process name" -ForegroundColor Red
    }

    # Start sleeping for 15 minutes
    Start-Sleep 900
}
