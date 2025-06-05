

function Get-RandomPassword {
    param (
        [int]$Length = 16
    )
    
    $upperChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lowerChars = "abcdefghijklmnopqrstuvwxyz"
    $numbers = "0123456789"
    $specialChars = "!@#$%&*"
    
    $allChars = $upperChars + $lowerChars + $numbers + $specialChars
    $password = ""
    
    # Ensure at least one of each character type
    $password += $upperChars[(Get-Random -Maximum $upperChars.Length)]
    $password += $lowerChars[(Get-Random -Maximum $lowerChars.Length)]
    $password += $numbers[(Get-Random -Maximum $numbers.Length)]
    $password += $specialChars[(Get-Random -Maximum $specialChars.Length)]
    
    # Fill the rest of the password
    for ($i = 4; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle the password characters
    $passwordArray = $password.ToCharArray()
    $shuffledArray = $passwordArray | Sort-Object {Get-Random}
    $shuffledPassword = -join $shuffledArray
    
    return $shuffledPassword
}

Get-RandomPassword 14
