# Journal des modifications

## 1.0.0 (2026-11-03)

- Première version.
- Lecture seule des identités d'agents Microsoft Entra Agent ID (`GET /v1.0/servicePrincipals/microsoft.graph.agentIdentity`).
- Lecture seule du registre des agents Copilot en préversion (`GET /v1.0/copilot/admin/catalog/packages`).
- Pagination avec `@odata.nextLink`.
- Objets PowerShell avec les colonnes Proprietaire et NiveauRisque à annoter.
- Exportation CSV et rapport HTML optionnels avec prise en charge de `-WhatIf` et `-Confirm`.
