
<# 

This function is used to download file using PowerShell
I'm using this function to automatically download then install application from iternet using RMM Solution like NinjaOne , Datto RMM, N-Able...etc
This function support auto retry when downloading fail.
it takes as parameters : 
URL : direct download file URL
Destination : destination folder where you ca save dowloaded file
RetryCount : maximum retry count by default 3.

example :
$URL = "https://drive.google.com/file2.zip"
$DestinationFolder = "C:\temp"
Download-File -Url $URL -Destination $DestinationFolder -RetryCount 5

#>

Function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$RetryCount = 3
    )

    Add-Type -AssemblyName "System.Net.Http"

    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $RetryCount) {
        try {
            $attempt++
            Write-Host "Attempt $($attempt) : Downloading $Url..."

            $clientHandler = New-Object System.Net.Http.HttpClientHandler
            $clientHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip, [System.Net.DecompressionMethods]::Deflate

            $client = [System.Net.Http.HttpClient]::new($clientHandler)
            $client.Timeout = [TimeSpan]::FromMinutes(10)

            $response = $client.GetAsync($Url).Result

            if (-not $response.IsSuccessStatusCode) {
                Write-Warning "HTTP error $($response.StatusCode) - $($response.ReasonPhrase)"
                throw "Download failed with HTTP error: $($response.StatusCode)"
            }

            $stream = $response.Content.ReadAsStreamAsync().Result
            $fileStream = [System.IO.File]::Create($Destination)
            $stream.CopyTo($fileStream)

            $fileStream.Close()
            $stream.Close()
            $client.Dispose()

            Write-Host "Download succeeded and saved to $Destination" -ForegroundColor Green
            $success = $true
        } catch {
            Write-Warning "Download failed: $_"
            Start-Sleep -Seconds 5
        }
    }

    if (-not $success) {
        Throw "Download failed after $RetryCount attempts."
    }
}

# Download Application
Download-File -Url $URL -Destination $DestinationFolder -RetryCount 5
