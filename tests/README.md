# Tester

## Offline, inga Exchange-rättigheter

Kör i en **ny process utan Exchange**. Mock-workflowet vägrar skugga riktiga Exchange-cmdlets.

```powershell
powershell.exe -NoProfile -File .\tests\Invoke-Tests.ps1
# Eller på en PowerShell 7-utvecklingsvärd:
pwsh -NoProfile -File ./tests/Invoke-Tests.ps1
```

Runnern kör native PowerShell-parser över alla `.ps1/.psm1/.psd1`, smoke, syntetiskt workflow och Pester 5.7.1. Inga dependencies installeras automatiskt. Installationssteg finns i [Microsoft-verktyg](../docs/microsoft-tools.md). Exit 0 kräver grön körning; misslyckande eller saknat Pester ger exit 1. Smoke kan köras separat utan Pester:

```powershell
powershell.exe -NoProfile -File .\tests\smoke\Invoke-SmokeTests.ps1
powershell.exe -NoProfile -File .\tests\smoke\Invoke-MockedWorkflow.ps1
```

Pester täcker config, typer/trösklar, explicit selektion, CSV, deduplicering, resultat/severity/exit, HTML/CSV-skydd, exakta bytevärden, mockad primary/archive-inventory, plan-modes, dubbletter, befintliga requests, anropsfel, mounted target, redan på mål och saknad arkivstatistik.

Syntetiskt workflow kör de riktiga operatörsskripten med test-cmdlets för inventory, plan, WhatIf, startens konservativa default, befintlig-request-blockering, monitoring och samlad rapport. Vad som inte är stubbat i valfri inventory-samling blir WARN; testet påstår inte serverhälsa. Temporary files städas efter testet. Enhetstester mockar endast Exchange/Windows-gränsen; de utför inga verkliga moves.

## Separat Exchange-labbgate — ingår aldrig i offline-runnern

Inga automatiska live-mutationstester är inkluderade. Följ denna explicita checklista på ett isolerat labb med syntetiska mailboxar och godkänd backup. Produktionsmiljö får inte användas som första verifiering.

- [ ] Kör syntax och Pester på **Windows PowerShell 5.1**; dokumentera OS/PowerShell/Pester-versioner.
- [ ] Verifiera exakt Exchange CU/SU/SE-build, tillåtna kombinationer, EMS och RBAC med HealthChecker.
- [ ] Inventory: user/shared/room/equipment, inget arkiv/lokalt arkiv/fjärrarkiv-indikator, kvoter och disconnected-statistik. Kontrollera ToBytes och deserialiserade storlekar.
- [ ] Testa mounted/unmounted mål, DAG/kopior, real CIM-mount-points och EDB/loggvolymmappning.
- [ ] Kontrollera readiness med lyckade och misslyckade native cmdlets, saknade rättigheter, certifikat, DNS, connectors, vdirs, queues, events och opt-in Test-Mailflow.
- [ ] Plan för Primary, Archive, Both, redan på mål, okänd statistik, olika alias och befintliga Completed/Failed/InProgress requests.
- [ ] WhatIf skapar noll requests; native New-MoveRequest WhatIf validerar MRS-förutsättningar.
- [ ] Explicit pilotstart: PrimaryOnly, ArchiveOnly och Both i separata urval, rätt mål och batch.
- [ ] Bekräfta AutoSuspended-standard; prova manuell completion och Scheduled CompleteAfter med dokumenterad tidszon.
- [ ] Simulera partiellt batchfel och journaling-fel; inga automatiska retries/removals får ske.
- [ ] Monitoring visar native egenskaper korrekt, inklusive archive targets, rate/duration, failures och item counts.
- [ ] Post-validation vid rätt/fel mål, CompletedWithWarning, saknad historik, arkivåtkomst och klient/mail-flow-tester.
- [ ] Granska samlad CSV/HTML och `.gitignore` med syntetisk data, spara signerad testredovisning utanför koden.

Dessa kontroller är markerade som manuella och Exchange-beroende, så frånvaron av Exchange kan inte orsaka falska live-testfailures i offline-sviten. Frånvaron är inte heller ett godkänt labbresultat. Faktisk status för denna leverans finns i [test-results](../docs/test-results.md).
