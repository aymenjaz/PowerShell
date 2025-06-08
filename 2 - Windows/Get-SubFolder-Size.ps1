
function getSubFolderSizes{
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true, position=1)]
        [string]$targetFolder
    )


    $Size=0

    if((Test-Path $targetFolder))
    {
        $Items=Get-ChildItem $targetFolder
        foreach($I in $Items)
        {
            if(-not $I.PSIsContainer){$Size+=$I.Length}
            else{$Size+=getSubFolderSizes $I.FullName}
        }

        return $Size
    }
}

function ConvertSize()
{
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true, position=1)]
        [string]$Size
    )
    if(($Size/1TB) -gt 1 )
    {
        $Size = [Math]::round($Size/1TB,2)
        return "$Size (TB)"
    }
    elseif(($Size/1GB) -gt 1)
    {
        $Size = [Math]::round($Size/1GB,2)
        return "$Size (GB)"
    }
    elseif(($Size/1MB) -gt 1)
    {
        $Size = [Math]::round($Size/1MB,2)
        return "$Size (MB)"
    }
    elseif(($Size/1KB) -gt 1)
    {
        $Size = [Math]::round($Size/1KB,2)
        return "$Size (KB)"
    }
    else
    {
        return "$Size (B)"
    }
}


$dir = "C:\temp"
ConvertSize(getSubFolderSizes $dir)
