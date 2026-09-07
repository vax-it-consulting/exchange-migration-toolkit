# Planering och kontrollerade mailbox moves

New-MoveRequest skapar en asynkron request; MRS utför arbetet. Toolkit är ett orkestreringslager för lokala mailbox moves i samma organisation. Det finns ingen all-mailbox-switch och ingen automatisk cleanup. [Microsofts cmdletreferens](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-moverequest?view=exchange-ps).

## Plan först

```powershell
$config = '.\config\local.config.psd1'
.\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -Identity 'pilot@example.test' -TargetDatabase DB-Target-01 -Mode Primary -Html
.\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -Identity 'one@example.test','two@example.test' -Mode Primary -Html
.\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -Mode Archive -ArchiveTargetDatabase DB-Archive-01 -Html
```

CSV är UTF-8, kommaseparerad med rubrik `Identity`, en identitet per rad. Den kan vara SMTP/alias/GUID som entydigt upplöses till en mailbox. Tomma rader/identiteter och jokertecken avvisas. Identiteter dedupliceras och olika alias till samma ExchangeGuid ger en planrad. Andra CSV-kolumner ignoreras: outputens redigerade target/action exekveras inte. Skapa separata explicita urval per mode/mål. En CSV med svensk semikolonseparator är inte det förväntade formatet.

| PlanMode | Start-parameter | Plan action | Vald payload |
| --- | --- | --- | --- |
| Primary (standard) | `-PrimaryOnly` eller inget komponentval | Move Primary | PrimaryBytes |
| Archive | `-ArchiveOnly` | Move Archive Only | ArchiveBytes |
| Both | `-IncludeArchive` | Move Primary + Archive | PrimaryBytes + ArchiveBytes |

Mode Both kräver lokalt arkiv på **alla** valda mailboxar. Mailbox utan arkiv körs i separat Primary-grupp. No Migration används när vald enda komponent redan ligger på rätt databas. Om en komponent i Both redan ligger rätt blir planen Review, så att operatören väljer rätt enda komponent. Review kan också bero på befintlig request, system-mailbox, fjärrarkiv eller okänd storlek. En Review-rad stoppar **hela starten innan första skrivning**.

Planen summerar känd vald EstimatedPayloadBytes och räknar Review. PrimaryBytes/ArchiveBytes finns per rad och kan summeras separat:

```powershell
$plan = .\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -Mode Primary
$plan | Measure-Object PrimaryBytes,ArchiveBytes,EstimatedPayloadBytes -Sum
```

Summan är ofullständig om ett fält är okänt. Payload exkluderar deleted/recoverable items, protokolloverhead, DAG-replikering och transaktionsloggar. Ingen tidsuppskattning ges. Planen är en ögonblicksbild; start gör samma preflight igen. Target måste finnas och vara mounted; primary-target används som kontext även vid ArchiveOnly och måste därför vara en giltig mounted databas i config.

## Dry run och start

```powershell
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Pilot-01 -PrimaryOnly -WhatIf
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Pilot-01 -PrimaryOnly
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -CsvPath .\private\archive-pilot.csv -BatchName Archive-01 -ArchiveOnly -ArchiveTargetDatabase DB-Archive-01 -WhatIf
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -CsvPath .\private\both-pilot.csv -BatchName Both-01 -IncludeArchive -TargetDatabase DB-Target-01 -ArchiveTargetDatabase DB-Archive-01 -WhatIf
```

Alla exempel med WhatIf måste granskas innan motsvarande verklig körning. Inga per-mailbox-identiteter hämtas implicit från config. Wrapperns WhatIf gör lokal plan/preflight och anropar aldrig New-MoveRequest. För MRS egna readiness-kontroller kan du dessutom uttryckligen köra native dry run:

```powershell
New-MoveRequest -Identity 'pilot@example.test' -TargetDatabase DB-Target-01 -PrimaryOnly -SuspendWhenReadyToComplete -WhatIf
```

Före start: go-beslut, HealthChecker, readiness, kapacitet, backup och lista ska vara granskade. Start visar tabell och använder SupportsShouldProcess/ConfirmImpact High. `-Confirm:$false` är ett uttryckligt sätt att slå av operatörsprompten; det ändrar inte preflight. Verktyget raderar aldrig en befintlig request, även om den är Completed. Om queryn för existerande requests misslyckas stoppas operationen, inte antas tomt resultat.

## Completion

Standard är `-CompletionMode Suspend`, vilket skickar `SuspendWhenReadyToComplete` till Exchange. Den uttryckliga switchen `-SuspendWhenReadyToComplete` väljer samma standard men får inte kombineras med Automatic/Scheduled. Microsoft rekommenderar CompleteAfter för schemaläggning; toolkit erbjuder båda så att en operatörsstyrd paus är möjlig.

```powershell
# Schematid tolkas i den körande serverns lokala tidszon om offset saknas.
$finish = (Get-Date).AddHours(6)
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Scheduled-01 -PrimaryOnly -CompletionMode Scheduled -CompleteAfter $finish -WhatIf
# Fullfölj automatiskt när MRS är redo; använd bara efter uttryckligt godkännande.
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -Identity 'pilot@example.test' -BatchName Auto-01 -PrimaryOnly -CompletionMode Automatic -WhatIf
```

CompleteAfter är tidigast tillåten slutförandetid, ingen garanti om deadline. Ange tid/zon i ändringsärendet. Schemat måste ligga i framtiden. Scheduled och CompleteAfter kräver varandra.

För manuellt slutförande av standardpausad request:

```powershell
Get-MoveRequest -Identity 'pilot@example.test' | Get-MoveRequestStatistics |
    Format-List Status,StatusDetail,PercentComplete,BadItemsEncountered,LargeItemsEncountered,Message
# Endast efter granskad AutoSuspended/redo-status och godkänt cutover-fönster:
Set-MoveRequest -Identity 'pilot@example.test' -SuspendWhenReadyToComplete:$false -Confirm
Resume-MoveRequest -Identity 'pilot@example.test' -Confirm
```

Kontrollera sedan Completed/CompletedWithWarning och faktisk databasplacering. För Scheduled-requests måste en eventuell framtida CompleteAfter också hanteras explicit; exemplen ovan gäller standardläget Suspend. [Set-MoveRequest](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-moverequest?view=exchange-ps), [Resume-MoveRequest](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/resume-moverequest?view=exchange-ps).

## Monitorera, pausa och avbryt

```powershell
.\src\Get-MoveRequestReport.ps1 -ConfigPath $config -BatchName Pilot-01 -Html
Suspend-MoveRequest -Identity 'pilot@example.test' -Confirm
# Spara status/evidens och granska läget innan eventuell avbrytning:
Remove-MoveRequest -Identity 'pilot@example.test' -WhatIf
# Kör utan WhatIf först när avbrytning är beslutad enligt rollback-planen.
```

Move-rapporten returnerar också pipelineobjekt. Transfer-rate finns bara när Exchange returnerar BytesTransferredPerMinute. StatusDetail är den verkliga native detaljstatusen; StalledReason kopierar detta fält och är ingen egen diagnos. `-IncludeFailureDetails` inkluderar rå Message i skyddad CSV/HTML, annars visas bara att text har utelämnats. Inga stora diagnostiska IncludeReport-exporter sparas automatiskt.

Om en start delvis lyckas och sedan misslyckas finns redan skapade requests kvar. Per-mailbox MoveJournal och Exchange är återstartsunderlaget. Kör inte om samma lista blint. Se [rollback-plan](rollback-plan.md) innan Remove-MoveRequest; en completed flytt återställs inte genom att ta bort requesten.
