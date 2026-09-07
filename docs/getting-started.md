# Kom igång — från inventering till pilotrapport

## 1. Förbered arbetsplatsen

Packa upp ZIP och öppna **Exchange Management Shell** från Start-menyn på en lämplig Exchange-server. Använd Windows PowerShell 5.1, inte en vanlig PowerShell 7-session för produktionsanrop. Kör HealthChecker i upphöjd EMS enligt dess krav. Övriga åtgärder kräver tilldelade Exchange RBAC-roller; lokal administratör ersätter inte Exchange-rättigheter.

```powershell
$PSVersionTable
Get-Command Get-Mailbox, Get-MailboxStatistics, Get-MailboxDatabase, Get-MoveRequest, New-MoveRequest
Set-Location C:\Tools\exchange-migration-toolkit
Get-Help .\src\Start-MailboxMigration.ps1 -Full
```

Saknas cmdlets: öppna korrekt EMS/installation, inte ett okänt internetbaserat bootstrap-script. Toolkit upprättar inga sessioner och hanterar inte credentials. Använd organisationens policy för kodgranskning, signering och execution policy; slå inte av policyn generellt.

## 2. Konfigurera och skydda output

```powershell
Copy-Item .\config\example.config.psd1 .\config\local.config.psd1
notepad .\config\local.config.psd1
$config = '.\config\local.config.psd1'
git check-ignore .\config\local.config.psd1
```

Ange verkliga namn enbart i den lokala filen. `SourceDatabases` avgränsar databasrapporter, inte mailbox-inventory: mailbox-vyn inventerar organisationens lokala user/shared/resource-mailboxar. Configens serverlistor styr serverkontroller. Target-parametrar på plan/start/post kan åsidosätta config; vid override måste även readiness köras med en config som motsvarar de faktiska målen.

Relativa output/logg-sökvägar utgår från repo-roten. Skapa en skyddad mapp per kund/uppdrag, begränsa behörigheter, kryptera enligt lokal policy och bestäm retention. `EnableMailFlowTest=$false` förhindrar testmeddelanden tills detta godkänts. Readiness skapar annars bara lokala rapporter och läser miljön.

## 3. Inventera och granska

```powershell
$inventory = .\src\Get-ExchangeInventory.ps1 -ConfigPath $config -IncludeDisconnected -Html -Verbose
$inventory | Select-Object DisplayName,PrimarySmtpAddress,MailboxType,PrimaryDatabase,PrimaryBytes,ArchiveDatabase,ArchiveBytes,TotalBytes,CollectionStatus
```

Output får unika UTC-tidsstämplar och filnamn, exempelvis `MailboxInventory-<tid>-<id>.csv`, motsvarande HTML och `InventoryCollectionStatus-<tid>-<id>.csv`. `-Verbose` visar sökvägar. Läs collection-statusrapporten: vissa miljöanrop kan ha misslyckats även om mailbox-tabellen finns. Tomt size-fält betyder okänd storlek, inte noll.

## 4. HealthChecker och pre-check

Följ [HealthChecker-guiden](microsoft-tools.md), granska rapporten och notera den exakta sökvägen:

```powershell
$healthReport = Read-Host 'Sökväg till granskad HealthChecker HTML-rapport'
$readiness = .\src\Test-ExchangeMigrationReadiness.ps1 -ConfigPath $config -HealthCheckerReportPath $healthReport -Html
$readiness | Format-Table Check,Target,Status,Detail -Wrap
```

PASS: just den kontrollen lyckades. WARN: osäkerhet eller avvikelse som måste bedömas. FAIL: stoppa och åtgärda innan flytt. INFO: insamlad information, avstängd kontroll eller manuell verifiering. Dokumentera vem som accepterat varje kvarstående WARN/INFO; en grön databasrad innebär inte ett generellt go-beslut.

## 5. Skapa uttrycklig pilotlista och plan

```powershell
New-Item -ItemType Directory -Path .\private -Force
@'
Identity
pilot@example.test
'@ | Set-Content .\private\pilot.csv -Encoding UTF8
$plan = .\src\New-ExchangeMigrationPlan.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -Mode Primary -Html
$plan | Format-Table PrimarySmtpAddress,PrimaryBytes,ArchiveBytes,MigrationAction,EstimatedPayloadBytes,PlanReason
```

Byt exemplet mot den godkända piloten. Granska även kvarvarande arkiv, kapacitet och No Migration. Planens CSV är evidens; redigerade action/target-kolumner exekveras aldrig. Kör samma selektion/mode vid start. Blanda inte olika modes i en CSV-batch i första versionen.

## 6. Dry run, start och monitorering

```powershell
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -BatchName Pilot-01 -PrimaryOnly -WhatIf
.\src\Start-MailboxMigration.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -BatchName Pilot-01 -PrimaryOnly
.\src\Get-MoveRequestReport.ps1 -ConfigPath $config -BatchName Pilot-01 -Html
```

Det andra kommandot ändrar Exchange efter bekräftelse. Standard är paus före slutförande. Vänta på lämpligt AutoSuspended-läge, granska statistik och följ completion-stegen i [migration.md](migration.md). Spara rapporten före cleanup.

## 7. Validera och skapa kundrapport

```powershell
.\src\Test-PostMigration.ps1 -ConfigPath $config -CsvPath .\private\pilot.csv -Mode Primary -HealthCheckerReportPath $healthReport -Html
Get-ChildItem .\output -Filter *.csv | Select-Object Name,LastWriteTimeUtc
# Ange de exakta rapporterna från samma fönster, en i taget. Inkludera inventory,
# collection status, serverdata, readiness, plan, move status och post-validation.
$reportFiles = @()
do {
    $path = Read-Host 'Exakt CSV-sökväg (tomt avslutar urval)'
    if ($path) { $reportFiles += $path }
} while ($path)
.\src\New-ExchangeMigrationReport.ps1 -ConfigPath $config -CsvPath $reportFiles -EnvironmentLabel 'Godkänt migrationsfönster' -HealthCheckerSummary 'Operatörens granskade slutsats; originalrapport bifogas separat.'
```

Vid annan OutputPath listar du den mappen i stället. Välj inte automatiskt alla historiska rapporter. Öppna HTML i webbläsare och granska scope, tider, varningar och failures. Bifoga original-HealthChecker, sign-off och manuella klienttestresultat till ändringsärendet. Gör separat beslut om cleanup och retention.
