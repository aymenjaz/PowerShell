# Function Get-ModifiedFiles
# to list modified files with many options
<#
-------------  Parametres ----------------------

-Directory     : (Obligatoire) spécifié le repertoire a scanner
-OutFolder     : (Facultatif)  True si vous voulez sauvegarder le résultat de scan au format CSV dans le répertoire C:\Report\
-PreviousDays  : (Facultatif)  Le nombre de jours que vous voulez utiliser dans la recherche , par défaut = 15 jour
-TreeMethod    : (Facultatif)  Unité de mesure des fichiers (1MB , 1GB ...) , par défaut = 1MB
-FileType      : (Facultatif)  Le type de fichier que vous voulez chercher (*.iso, *.mdf ...) , si non il vas chercher tous les fichiers , par défaut = *

#>

       #nom du fichier csv

#------------------------------------  fonction de recherche ----------------------------------------
function Get-ModifiedFiles
{

	[CmdletBinding()]
	param(
		[Parameter(Mandatory= $true )]
		[string] $Directory,

        [Parameter(Mandatory= $false )]
        [string] $OutFolder = $false,

        [Parameter(Mandatory= $false )]
        [string] $PreviousDays = 15,

        [Parameter(Mandatory= $false )]
        [string] $TreeMethod = "1MB",

        [Parameter(Mandatory= $false )]
        [string[]] $FileType = "*"

	)
	$OutPutFolder = 'C:\Report\'       #va etre utilisé si vous voulez sauvegarder le résultat de scan au format CSV dans le répertoire C:\Report\
    $OUTFileName = 'Scan.csv'   
    
    if((Test-Path $Directory) -eq $true)
    {
        if($OutFolder -eq $true)
        {
            if((Test-Path $OutPutFolder) -eq $false)
            {
                New-Item -ItemType Directory -Path $OutFolder
            }
            
            $OutPut = $OutPutFolder+$OUTFileName
            Get-ChildItem -Path $Directory -Include $FileType -Recurse  | 
            Select-Object Name , @{label = "Size $($TreeMethod)"; expression = {[math]::Round($_.Length / $TreeMethod,2) }}, LastWriteTime , FullName  | Sort-Object -Descending "Size $($TreeMethod)" |
            Where-Object { ($_.LastWriteTime -gt (Get-Date).AddDays(-$PreviousDays)) }  | Export-Csv $OutPut -Delimiter ';' -Encoding UTF8 -Force

        }
        else 
        {
            
            Get-ChildItem -Path $Directory -Include  $FileType -Recurse | 
            Select-Object Name , @{label = "Size $($TreeMethod)"; expression = { [math]::Round($_.Length / $TreeMethod,2)  }}, LastWriteTime , FullName | Sort-Object -Descending "Size $($TreeMethod)" |
            Where-Object { ($_.LastWriteTime -gt (Get-Date).AddDays(-$PreviousDays)) }
        }
    }
    else 
    {
        Write-Host "Le répertoire $($Directory) n'est pas existant , veillez saisir un repertoire valide"   
    }
}
#------------------------------------------  fin de la fonction de recherche --------------------------------------------------

<#
-------------  Parametres ----------------------

-Directory     : (Obligatoire) spécifié le repertoire a scanner
-OutFolder     : (Facultatif)  True si vous voulez sauvegarder le résultat de scan au format CSV dans le répertoire C:\Report\
-PreviousDays  : (Facultatif)  Le nombre de jours que vous voulez utiliser dans la recherche , par défaut = 15 jour
-TreeMethod    : (Facultatif)  Unité de mesure des fichiers (1MB , 1GB ...) , par défaut = 1MB
-FileType      : (Facultatif)  Le type de fichier que vous voulez chercher (*.iso, *.mdf ...) , si non il vas chercher tous les fichiers , par défaut = *

#>

# Voici les exemples d'utilisation de la fonction que j'ai developpé

#-------------------------- EXAMPLE 1 --------------------------
Get-ModifiedFiles -Directory 'C:\Aymen\'
        
#-------------------------- EXAMPLE 2 --------------------------
Get-ModifiedFiles -Directory 'C:\Aymen\' -PreviousDays 20 
       
#-------------------------- EXAMPLE 3 --------------------------
Get-ModifiedFiles -Directory 'C:\Aymen\' -PreviousDays 15 -TreeMethod 1MB 
        
#-------------------------- EXAMPLE 4 --------------------------
Get-ModifiedFiles -Directory 'C:\Aymen\' -PreviousDays 25 -TreeMethod 1MB -FileType *.iso,*.mp4,*.csv

#-------------------------- EXAMPLE 5 --------------------------
Get-ModifiedFiles -Directory 'C:\Aymen\' -PreviousDays 25 -TreeMethod 1MB -FileType *.iso,*.mp4,*.csv -OutFolder true
