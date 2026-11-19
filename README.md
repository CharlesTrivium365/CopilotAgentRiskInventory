# CopilotAgentRiskInventory

CopilotAgentRiskInventory est un script PowerShell en lecture seule qui dresse un premier inventaire des agents Copilot d'un locataire Microsoft 365. Il lit les identités d'agents de Microsoft Entra Agent ID ainsi que les packages du registre des agents Copilot (préversion). Il prépare ensuite deux colonnes à remplir : le propriétaire de chaque agent et son niveau de risque.

Il accompagne l'article [Gouvernance des agents Copilot : classer par niveau de risque avant d'automatiser](https://trivium365.com/blog/gouvernance-agents-copilot-niveau-de-risque-avant-automatiser/).

## Pourquoi maintenant

Le 22 septembre 2026, Microsoft a publié sur le blogue Copilot Studio un billet qui décrit une gouvernance des agents en trois parties : observer en continu, répondre de façon proportionnée au risque et automatiser là où c'est approprié. Le billet rappelle que tous les agents ne présentent pas le même risque. Il propose de situer chaque agent selon son identité, ses permissions, son accès aux données, son degré d'autonomie et ses actions disponibles.

Avant de répondre au risque ou d'automatiser quoi que ce soit, il faut savoir quels agents existent et qui en est responsable. Ce script sert à cette première étape.

## Ce que fait l'outil

- Lit les identités d'agents avec `GET https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity` (permission AgentIdentity.Read.All).
- Lit le registre des agents avec `GET https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages` (permission CopilotPackages.Read.All, rôle AI Administrator, libellé « preview »).
- Suit la pagination `@odata.nextLink` pour lire toutes les pages.
- Retourne des objets PowerShell avec les propriétés Source, Nom, Id, Proprietaire, NiveauRisque et Donnees.
- Sur demande, exporte les fichiers `identites-agents.csv` et `registre-agents.csv` ainsi qu'un rapport HTML simple `rapport-agents.html`.
- Affiche les totaux avec `Write-Information` (visibles avec `-InformationAction Continue`).

Le script n'envoie que des requêtes GET. Il ne modifie rien dans le locataire. Il n'a donc pas de paramètre `-Apply`. Les seules écritures sont des fichiers locaux : elles passent par ShouldProcess et respectent `-WhatIf` et `-Confirm`.

## Prérequis

- Windows PowerShell 5.1 ou PowerShell 7.
- Le module Microsoft.Graph.Authentication (Microsoft Graph PowerShell).
- Un compte qui détient le rôle AI Administrator, exigé pour lire le registre des agents.
- Les permissions déléguées minimales AgentIdentity.Read.All et CopilotPackages.Read.All. Le script ne demande que celles des sources choisies avec `-Include`.
- Une licence Microsoft Agent 365 : la documentation Microsoft Learn indique que l'API de gestion des packages l'exige.

À la première connexion, Microsoft Graph peut demander un consentement pour les permissions demandées.

## Installation

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

Téléchargez ensuite le fichier `Get-CopilotAgentRiskInventory.ps1` ou clonez le dépôt.

## Exemples d'utilisation

Afficher les totaux et obtenir les agents sous forme d'objets :

```powershell
$inventaire = .\Get-CopilotAgentRiskInventory.ps1 -InformationAction Continue
$inventaire | Format-Table -Property Source, Nom, Id -AutoSize
```

Exporter les CSV et le rapport HTML dans un dossier :

```powershell
.\Get-CopilotAgentRiskInventory.ps1 -OutputPath .\rapports -HtmlReport
```

Voir les fichiers qui seraient écrits sans rien écrire :

```powershell
.\Get-CopilotAgentRiskInventory.ps1 -OutputPath .\rapports -HtmlReport -WhatIf
```

Réutiliser une session existante et ne lire que les identités d'agents :

```powershell
Connect-MgGraph -Scopes "AgentIdentity.Read.All"
.\Get-CopilotAgentRiskInventory.ps1 -Include AgentIdentity -SkipConnect
```

Ouvrez ensuite les fichiers CSV dans Excel et remplissez les colonnes Proprietaire et NiveauRisque. Les agents pour lesquels personne ne se présente comme propriétaire sont de bons premiers candidats à une revue.

## Exemple de sortie

L'exemple suivant est fictif. Les noms et les identifiants ont été inventés pour illustrer le format.

```text
Identités d'agents dans Entra : 2
Packages dans le registre des agents (préversion) : 1

Source                Nom                            Id
------                ---                            --
EntraAgentId          Agent Comptabilité (fictif)    00000000-0000-0000-0000-000000000001
EntraAgentId          Agent Soutien TI (fictif)      00000000-0000-0000-0000-000000000002
RegistreAgentsCopilot
```

Pour les packages du registre, Nom et Id restent vides : le JSON brut de chaque package se trouve dans la propriété Donnees et ses champs deviennent des colonnes dans `registre-agents.csv`.

## Grille de risque de référence

Cette grille vient de l'article. Elle s'appuie sur les cinq critères du billet de Microsoft mais Microsoft ne la publie pas. Le rapport HTML la reprend.

| Niveau | Ce que fait l'agent | Ce qui est demandé |
| --- | --- | --- |
| 1 | Répond à partir de contenu interne approuvé, sans action dans un autre système | Un propriétaire nommé et le respect des règles générales de publication |
| 2 | Lit des données d'affaires ou des sites SharePoint plus sensibles | Une revue des sources de connaissances par l'équipe TI avant la mise en service |
| 3 | Pose des actions (écrit, envoie, modifie) ou touche des données sensibles | Une approbation explicite, un propriétaire de secours et une revue périodique |

Un agent qui change de niveau, par exemple après l'ajout d'un connecteur vers un CRM, devrait déclencher une revue.

## Limites connues

- La migration des agents Copilot Studio vers Entra Agent ID est en préversion : une partie des agents peut ne pas apparaître dans la liste des identités d'agents.
- Le registre des agents est en préversion. Ses propriétés ne sont pas détaillées dans les sources de ce projet : le script les exporte telles quelles et les valeurs imbriquées deviennent du JSON compact.
- Si la lecture du registre échoue, vérifiez d'abord la licence Microsoft Agent 365 puis le rôle AI Administrator. Le script affiche un avertissement et continue avec l'autre source.
- Les agents qui vivent hors de l'écosystème Microsoft ne sont vus par aucun de ces deux appels.
- Le niveau de risque n'est pas calculé automatiquement : il reste une décision humaine fondée sur votre grille.
- Le script n'a pas été validé dans votre locataire. Testez-le d'abord avec un compte de test.

## Sources

- Article : [Gouvernance des agents Copilot : classer par niveau de risque avant d'automatiser](https://trivium365.com/blog/gouvernance-agents-copilot-niveau-de-risque-avant-automatiser/)
- Microsoft, blogue Copilot Studio (22 septembre 2026) : [Governance is becoming agentic, too: How enterprises can operate AI at scale](https://techcommunity.microsoft.com/blog/copilot-studio-blog/governance-is-becoming-agentic-too-how-enterprises-can-operate-ai-at-scale/4556820)
- Microsoft Learn : [Migration des agents Copilot Studio vers Entra Agent ID (préversion)](https://learn.microsoft.com/en-us/microsoft-copilot-studio/govern-migrate-api-entra-agent-identity)

## Licence

MIT. Voir le fichier [LICENSE](LICENSE).


## Démonstration en vidéo

https://www.youtube.com/watch?v=OyEKhgJYjZI
