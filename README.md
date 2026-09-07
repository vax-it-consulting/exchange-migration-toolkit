# Exchange Migration Toolkit

Ett litet PowerShell-baserat arbetsflöde för konsultuppdrag med **lokala mailbox moves inom samma Exchange-organisation**, avsett för Exchange Server 2019 och Subscription Edition (SE). Separata primary- och archive-data är kärnan. Microsofts cmdlets utför arbetet; Microsoft CSS-Exchange HealthChecker ansvarar för generell serverhälsa.

**Leveransstatus: initial implementation, inte produktionsgodkänd.** PowerShell/Pester kunde inte köras i den levererande Astra-miljön. Läs [testresultat](docs/test-results.md) och kör testsviten och en Exchange-labbpilot före produktion. Definition of Done är därför inte helt uppfylld.

Toolkit installerar eller uppgraderar inte Exchange. Det hanterar inte cross-forest, hybrid/Exchange Online, public folders, arbitration/system mailboxes eller avveckling av servrar. Versionsnamnen innebär inte att varje kombination av CU/SU stöds. Kontrollera aktuell [uppgraderingsväg](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/deploy-new-installations/upgrade-to-exchange-server-se) och [systemkrav/samexistens](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/system-requirements) inför uppdraget. En in-place-uppgradering från en tillåten 2019-version kan vara lämpligare än serverbyte; då behövs inte mailbox moves för själva uppgraderingen.

## Förutsättningar och installation

- Produktion: Windows PowerShell 5.1, 64-bitars Exchange Management Shell (EMS) med cmdlets från den aktuella on-premises-miljön. PowerShell 7 är endast en möjlig offline-testmiljö här.
- RBAC för läsning samt Move Mailboxes-rättigheter för start. CIM/eventlogg/HealthChecker behöver ytterligare Windows-rättigheter och fungerande fjärråtkomst. Se [getting started](docs/getting-started.md).
- Git för versionshantering; Pester **5.7.1** för enhetstester. Ingen runtime-download görs av skripten.
- HealthChecker installeras och granskas manuellt enligt [Microsoft-verktyg](docs/microsoft-tools.md). Övriga skript fungerar utan det, men saknad health-evidens ger WARN.

Packa upp leveransens ZIP: den innehåller källkod och `.git` med första commit. Alternativt publicera repot i en godkänd privat Git-tjänst och klona med den URL tjänsten ger:

```powershell
$repositoryUrl = Read-Host 'Ange godkänd Git-URL'
git clone $repositoryUrl exchange-migration-toolkit
Set-Location .\exchange-migration-toolkit
Copy-Item .\config\example.config.psd1 .\config\local.config.psd1
notepad .\config\local.config.psd1
```

Alla exempelvärden använder `example.test`. Ersätt dem i den ignorerade lokala konfigurationen. Relativa `OutputPath`/`LogPath` utgår från repo-roten, oavsett aktuell arbetskatalog. Välj kundgodkänd åtkomstskyddad lagring för produktionsrapporter. Toolkit ändrar inte ACL eller kryptering åt dig.

## Normalt arbetsflöde

1. Inventory — primary och archive inventeras separat.
2. Kör och granska Microsoft HealthChecker; kör migration pre-check.
3. Review results — dokumentera blockers, kapacitet och operatörsbeslut.
4. Skapa migrationsplan för uttryckligen valda mailboxar; granska sedan `-WhatIf`.
5. Start migration — primary-only och paus före completion är standard.
6. Monitor move requests — följ progress, stalls och fel.
7. Complete migration — explicit native EMS-åtgärd i godkänt fönster.
8. Post-validation — placering, statistik, historik och manuella klienttester.
9. Cleanup/documentation — spara evidens och kundrapport före separat beslutad cleanup.

```powershell
$config = '.\config\local.config.psd1'
.\src\Get-ExchangeInventory.ps1 -ConfigPath $config -IncludeDisconnected -Html -Verbose
# Kör HealthChecker enligt docs/microsoft-tools.md innan sign-off.
.\src\Test-ExchangeMigrationReadiness.ps1 -ConfigPath $config -Html
.\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -Identity 'pilot@example.test' -Mode Primary -Html
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Pilot-01 -PrimaryOnly -WhatIf
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Pilot-01 -PrimaryOnly
.\src\Get-MoveRequestReport.ps1 -ConfigPath $config -BatchName Pilot-01 -Html
# Completion görs först efter kontroll enligt docs/migration.md.
.\src\Test-PostMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -Mode Primary -Html
```

Start kräver uttryckliga identiteter eller en CSV med `Identity`. Den tar inte mailboxar ur config eller inventory automatiskt. En befintlig move request, även Completed, måste granskas separat. Inga requests skrivs över eller raderas. `-WhatIf` gör läsande preflight och visar planen men anropar inte `New-MoveRequest`, och skapar inte logg/rapportfiler. Native MRS-WhatIf kan komplettera enligt migrationsguiden.

## Filer och ansvar

| Sökväg | Innehåll |
| --- | --- |
| `src/Get-ExchangeInventory.ps1` | Mailboxar, primary/archive-statistik och konfiguration |
| `src/New-ExchangeMigrationPlan.ps1` | Skrivskyddad plan och vald datamängd |
| `src/Test-ExchangeMigrationReadiness.ps1` | Migrationsspecifika kontroller |
| `src/Start-MailboxMigration.ps1` | Konservativ wrapper för New-MoveRequest |
| `src/Get-MoveRequestReport.ps1` | Progress, storlek, stalls och felindikatorer |
| `src/Test-PostMigration.ps1` | Placering, läsbarhet, completion och driftkontroller |
| `src/New-ExchangeMigrationReport.ps1` | Samlad fristående HTML från valda CSV-filer |
| `src/Common/` | Små interna hjälpmoduler för config, export, data och kontroller |
| `config/` | Endast säker example config versionshanteras |
| `docs/` | Operatörsguider, runbook, återställning och teststatus |
| `tests/unit/`, `tests/smoke/` | Pester och fristående tester utan Exchange |
| `output/`, `logs/` | Ignorerat genererat material |

## Säkerhet och begränsningar

Lägg aldrig credentials, API-nycklar, lösenord, produktionskonfiguration, mailbox-listor, interna IP-adresser, exporter eller loggar i Git. `.gitignore` skyddar vanliga filtyper och mappar men är ingen sekretessgaranti: även en Markdown-fil kan läcka data och `git add -f` kringgår ignore. Granska `git diff --cached` före commit. Toolkit använder befintlig EMS-session och lagrar inga credentials.

Generiska loggar innehåller enbart UTC-tid, fasta händelsekoder och räknare. Identiteten för varje initierad mailbox lagras i en separat **MoveJournal-rapport** under skyddad output. CSV/HTML innehåller person- och infrastrukturuppgifter. Feltext i move-rapporter kräver `-IncludeFailureDetails`. HTML-escape och skydd mot formelliknande CSV-celler används vid export. Start avbryts vid första skrivfel; tidigare skapade requests finns kvar. En journaling-failure efter ett lyckat Exchange-anrop kan kräva manuell rekonstruktion från Exchange.

Inga automatiska retries, completion, data-loss-flaggor eller cleanup. PASS betyder endast att den namngivna kontrollen lyckades. INFO kan betyda att manuell kontroll återstår. Kapacitetsbedömning inkluderar inte automatiskt loggar, recoverable items, säkerhetsmarginal eller alla DAG-kopior. Se [arkitektur och begränsningar](docs/architecture.md).

## Dokumentation och tester

- [Kom igång och komplett pilot](docs/getting-started.md)
- [Inventory och arkivstrategi](docs/inventory.md)
- [Microsoft-verktyg och HealthChecker](docs/microsoft-tools.md)
- [Pre-checks](docs/prechecks.md), [migration/plan/completion](docs/migration.md), [validering](docs/validation.md)
- [Felsökning](docs/troubleshooting.md), [runbook](docs/migration-runbook.md), [rollback-plan](docs/rollback-plan.md)
- [Tester och Exchange-labbgate](tests/README.md), [faktiska testresultat](docs/test-results.md)

I en separat PowerShell-process utan Exchange:

```powershell
powershell.exe -NoProfile -File .\tests\Invoke-Tests.ps1
```

Licens: [MIT](LICENSE). Inga Microsoft-skript distribueras i repot; respektive verktygs licens gäller separat.
