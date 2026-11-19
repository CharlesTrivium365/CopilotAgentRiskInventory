<#
.SYNOPSIS
    Inventaire en lecture seule des agents Copilot pour préparer une grille de niveau de risque.

.DESCRIPTION
    Ce script interroge Microsoft Graph en lecture seule pour dresser un premier portrait des agents
    du locataire :

    - les identités d'agents de Microsoft Entra Agent ID
      (GET /v1.0/servicePrincipals/microsoft.graph.agentIdentity, permission AgentIdentity.Read.All) ;
    - les packages du registre des agents Copilot, en préversion
      (GET /v1.0/copilot/admin/catalog/packages, permission CopilotPackages.Read.All, rôle AI Administrator).

    Chaque agent est retourné sous forme d'objet PowerShell avec deux colonnes vides, Proprietaire et
    NiveauRisque, à remplir selon votre grille de risque. Les propriétés retournées par l'API du registre
    (préversion) ne sont pas documentées dans les sources de ce projet : chaque package est donc conservé
    tel quel, en JSON, dans la propriété Donnees et exporté en colonnes brutes dans le CSV.

    Le script ne modifie rien dans le locataire. Les seules écritures sont locales (CSV et HTML) et passent
    par ShouldProcess : -WhatIf et -Confirm sont donc pris en charge.

.PARAMETER Include
    Sources à interroger. Valeurs possibles : AgentIdentity (identités d'agents Entra Agent ID) et
    PackageRegistry (registre des agents Copilot, préversion). Par défaut, les deux sont interrogées.
    Seules les permissions nécessaires aux sources choisies sont demandées à la connexion.

.PARAMETER OutputPath
    Dossier où écrire les fichiers identites-agents.csv et registre-agents.csv (et rapport-agents.html
    avec -HtmlReport). Le dossier est créé au besoin. Sans ce paramètre, aucun fichier n'est écrit et
    seuls les objets PowerShell sont retournés.

.PARAMETER HtmlReport
    Produit aussi un rapport HTML simple (totaux, grille de risque de référence et tableaux) dans le
    dossier indiqué par -OutputPath. Exige -OutputPath.

.PARAMETER SkipConnect
    N'appelle pas Connect-MgGraph. À utiliser si une session Microsoft Graph est déjà ouverte avec les
    permissions AgentIdentity.Read.All et CopilotPackages.Read.All.

.EXAMPLE
    .\Get-CopilotAgentRiskInventory.ps1 -InformationAction Continue

    Se connecte à Microsoft Graph, affiche les totaux et retourne les agents sous forme d'objets.

.EXAMPLE
    .\Get-CopilotAgentRiskInventory.ps1 -OutputPath .\rapports -HtmlReport

    Exporte les deux fichiers CSV et un rapport HTML dans le dossier .\rapports.

.EXAMPLE
    .\Get-CopilotAgentRiskInventory.ps1 -OutputPath .\rapports -HtmlReport -WhatIf

    Interroge Microsoft Graph et indique les fichiers qui seraient écrits sans les écrire.

.EXAMPLE
    Connect-MgGraph -Scopes "AgentIdentity.Read.All"
    .\Get-CopilotAgentRiskInventory.ps1 -Include AgentIdentity -SkipConnect | Sort-Object -Property Nom

    Réutilise une session existante et ne lit que les identités d'agents Entra Agent ID.

.INPUTS
    Aucune.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Propriétés : Source, Nom, Id, Proprietaire, NiveauRisque, Donnees.

.NOTES
    Version : 1.0.0
    Auteur  : Charles Jenkins
    Module  : Microsoft.Graph.Authentication
    Lecture seule : aucune requête autre que GET n'est envoyée à Microsoft Graph.

.LINK
    https://trivium365.com/blog/gouvernance-agents-copilot-niveau-de-risque-avant-automatiser/

.LINK
    https://learn.microsoft.com/en-us/microsoft-copilot-studio/govern-migrate-api-entra-agent-identity
#>
#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [ValidateSet('AgentIdentity', 'PackageRegistry')]
    [string[]]$Include = @('AgentIdentity', 'PackageRegistry'),

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [switch]$HtmlReport,

    [switch]$SkipConnect
)

function Get-GraphCollection {
    <#
    .SYNOPSIS
        Lit toutes les pages d'une collection Microsoft Graph en suivant @odata.nextLink.
    .PARAMETER Uri
        Adresse complète de la première page.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    while ($nextUri) {
        Write-Verbose -Message "GET $nextUri"
        $page = Invoke-MgGraphRequest -Method GET -Uri $nextUri -ErrorAction Stop
        foreach ($entry in $page['value']) {
            $items.Add($entry)
        }
        $nextUri = $page['@odata.nextLink']
    }
    return , $items.ToArray()
}

function ConvertTo-FlatRecord {
    <#
    .SYNOPSIS
        Convertit un objet Graph en dictionnaire plat ; les valeurs imbriquées deviennent du JSON compact.
    .PARAMETER InputObject
        Dictionnaire retourné par Invoke-MgGraphRequest.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$InputObject
    )

    $record = [ordered]@{}
    foreach ($key in $InputObject.Keys) {
        $value = $InputObject[$key]
        $isNested = ($value -is [System.Collections.IDictionary]) -or
            (($value -is [System.Collections.IEnumerable]) -and ($value -isnot [string]))
        if ($isNested) {
            $record[[string]$key] = ConvertTo-Json -InputObject $value -Depth 10 -Compress
        }
        else {
            $record[[string]$key] = $value
        }
    }
    return $record
}

if ($HtmlReport -and -not $OutputPath) {
    throw 'Le paramètre -HtmlReport exige -OutputPath.'
}

$agentIdentityUri = 'https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity'
$packageRegistryUri = 'https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages'

$readAgentIdentity = $Include -contains 'AgentIdentity'
$readPackageRegistry = $Include -contains 'PackageRegistry'

if (-not $SkipConnect) {
    $scopes = [System.Collections.Generic.List[string]]::new()
    if ($readAgentIdentity) { $scopes.Add('AgentIdentity.Read.All') }
    if ($readPackageRegistry) { $scopes.Add('CopilotPackages.Read.All') }
    Connect-MgGraph -Scopes $scopes.ToArray() -ErrorAction Stop
}

$identityRows = [System.Collections.Generic.List[object]]::new()
$packageRows = [System.Collections.Generic.List[object]]::new()
$packageRecords = [System.Collections.Generic.List[object]]::new()

if ($readAgentIdentity) {
    try {
        $identities = Get-GraphCollection -Uri $agentIdentityUri -ErrorAction Stop
        foreach ($identity in $identities) {
            $identityRows.Add([pscustomobject]@{
                    Source       = 'EntraAgentId'
                    Nom          = $identity['displayName']
                    Id           = $identity['id']
                    Proprietaire = $null
                    NiveauRisque = $null
                    Donnees      = $null
                })
        }
        Write-Information -MessageData "Identités d'agents dans Entra : $($identityRows.Count)"
    }
    catch {
        Write-Warning -Message ("Lecture des identités d'agents impossible : {0} " -f $_.Exception.Message +
            'Vérifiez la permission AgentIdentity.Read.All.')
    }
}

if ($readPackageRegistry) {
    try {
        $packages = Get-GraphCollection -Uri $packageRegistryUri -ErrorAction Stop
        foreach ($package in $packages) {
            $packageRecords.Add((ConvertTo-FlatRecord -InputObject $package))
            $packageRows.Add([pscustomobject]@{
                    Source       = 'RegistreAgentsCopilot'
                    Nom          = $null
                    Id           = $null
                    Proprietaire = $null
                    NiveauRisque = $null
                    Donnees      = ConvertTo-Json -InputObject $package -Depth 10 -Compress
                })
        }
        Write-Information -MessageData "Packages dans le registre des agents (préversion) : $($packageRows.Count)"
    }
    catch {
        Write-Warning -Message ("Lecture du registre des agents impossible : {0} " -f $_.Exception.Message +
            'Vérifiez le rôle AI Administrator, la permission CopilotPackages.Read.All ' +
            "et la licence Microsoft Agent 365 exigée par l'API de gestion des packages (préversion).")
    }
}

$sortedIdentityRows = @($identityRows | Sort-Object -Property Nom)

if ($OutputPath) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($OutputPath, 'Créer le dossier de sortie')) {
            $null = New-Item -Path $OutputPath -ItemType Directory -Force
        }
    }

    if ($readAgentIdentity) {
        $identityCsv = Join-Path -Path $OutputPath -ChildPath 'identites-agents.csv'
        if ($PSCmdlet.ShouldProcess($identityCsv, "Exporter les identités d'agents en CSV")) {
            $sortedIdentityRows |
                Select-Object -Property Nom, Id, Proprietaire, NiveauRisque |
                Export-Csv -LiteralPath $identityCsv -NoTypeInformation -Encoding UTF8
        }
    }

    if ($readPackageRegistry -and $packageRecords.Count -gt 0) {
        # Les packages n'ont pas tous forcément les mêmes propriétés : on réunit toutes les colonnes.
        $columns = [System.Collections.Generic.List[string]]::new()
        foreach ($record in $packageRecords) {
            foreach ($key in $record.Keys) {
                if (-not $columns.Contains($key)) { $columns.Add($key) }
            }
        }
        foreach ($annotationColumn in @('Proprietaire', 'NiveauRisque')) {
            if (-not $columns.Contains($annotationColumn)) { $columns.Add($annotationColumn) }
        }

        $packageCsv = Join-Path -Path $OutputPath -ChildPath 'registre-agents.csv'
        if ($PSCmdlet.ShouldProcess($packageCsv, 'Exporter le registre des agents en CSV')) {
            $packageRecords |
                ForEach-Object {
                    $row = [ordered]@{}
                    foreach ($column in $columns) { $row[$column] = $_[$column] }
                    [pscustomobject]$row
                } |
                Export-Csv -LiteralPath $packageCsv -NoTypeInformation -Encoding UTF8
        }
    }

    if ($HtmlReport) {
        $htmlPath = Join-Path -Path $OutputPath -ChildPath 'rapport-agents.html'
        if ($PSCmdlet.ShouldProcess($htmlPath, 'Écrire le rapport HTML')) {
            $head = @'
<meta charset="utf-8">
<title>Inventaire des agents Copilot</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 2em; }
table { border-collapse: collapse; margin-bottom: 2em; }
th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: left; vertical-align: top; }
th { background: #eee; }
</style>
'@
            $riskGrid = @(
                [pscustomobject]@{
                    Niveau               = 1
                    'Ce que fait l''agent' = 'Répond à partir de contenu interne approuvé, sans action dans un autre système'
                    'Ce qui est demandé'   = 'Un propriétaire nommé et le respect des règles générales de publication'
                }
                [pscustomobject]@{
                    Niveau               = 2
                    'Ce que fait l''agent' = 'Lit des données d''affaires ou des sites SharePoint plus sensibles'
                    'Ce qui est demandé'   = 'Une revue des sources de connaissances par l''équipe TI avant la mise en service'
                }
                [pscustomobject]@{
                    Niveau               = 3
                    'Ce que fait l''agent' = 'Pose des actions (écrit, envoie, modifie) ou touche des données sensibles'
                    'Ce qui est demandé'   = 'Une approbation explicite, un propriétaire de secours et une revue périodique'
                }
            )

            $fragments = [System.Collections.Generic.List[string]]::new()
            $fragments.Add('<h1>Inventaire des agents Copilot (lecture seule)</h1>')
            $fragments.Add("<p>Produit le $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Identités d'agents Entra : $($identityRows.Count). Packages du registre (préversion) : $($packageRows.Count).</p>")
            $fragments.Add(($riskGrid | ConvertTo-Html -Fragment -PreContent '<h2>Grille de risque de référence</h2>' | Out-String))

            if ($sortedIdentityRows.Count -gt 0) {
                $fragments.Add(($sortedIdentityRows |
                            ConvertTo-Html -Fragment -Property Nom, Id, Proprietaire, NiveauRisque -PreContent "<h2>Identités d'agents (Entra Agent ID)</h2>" |
                            Out-String))
            }
            else {
                $fragments.Add("<h2>Identités d'agents (Entra Agent ID)</h2><p>Aucune identité d'agent lue.</p>")
            }

            if ($packageRows.Count -gt 0) {
                $fragments.Add(($packageRows |
                            ConvertTo-Html -Fragment -Property Proprietaire, NiveauRisque, Donnees -PreContent '<h2>Registre des agents Copilot (préversion, données brutes)</h2>' |
                            Out-String))
            }
            else {
                $fragments.Add('<h2>Registre des agents Copilot (préversion)</h2><p>Aucun package lu.</p>')
            }

            ConvertTo-Html -Head $head -Body ($fragments -join [Environment]::NewLine) |
                Set-Content -LiteralPath $htmlPath -Encoding UTF8
        }
    }
}

Write-Output -InputObject $sortedIdentityRows
Write-Output -InputObject $packageRows.ToArray()
