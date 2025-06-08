$menu = @"

*****************************************************************************

Select option :


1) Option 1                                    5) Option 5

2) Option 2                                    6) Option 6

3) Option 3                                    7) Option 7

4) Option 4                                    8) Option 8


Click x to exit


*****************************************************************************

Entrer your choice
"@

do
{
    cmd /c color 71
    $Selection = Read-Host -prompt $menu
    clear-host
    Switch($Selection)
    {
        1 {Write-Host 'Option 1'; pause}
        2 {Write-Host 'Option 2'; pause}
        3 {Write-Host 'Option 3'; pause}
        4 {Write-Host 'Option 4'; pause}
        5 {Write-Host 'Option 5'; pause}
        6 {Write-Host 'Option 6'; pause}
        7 {Write-Host 'Option 7'; pause}
        8 {Write-Host 'Option 8'; pause}

        default{Write-Host 'Please Enter Number Between 1 and 8'; pause -foregroundColor DarkGray -BackgroundColor Green }
    }
    
}Until($Selection -eq 'x')

switch($PSVersionTable.PSEdition)
{
    'Core' {cmd /c color 07}
    'Desktop' {cmd /c color 56}
    Default {cmd /c color 56}
} 

