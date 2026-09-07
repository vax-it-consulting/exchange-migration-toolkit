# Eftervalidering och kundrapport

```powershell
.\src\Test-PostMigration.ps1 -ConfigPath .\config\local.config.psd1 -CsvPath .\private\pilot.csv -Mode Primary -Html
.\src\Test-PostMigration.ps1 -ConfigPath .\config\local.config.psd1 -Identity 'pilot@example.test' -Mode Archive -ArchiveTargetDatabase DB-Archive-01 -Html
```

Använd exakt samma valda mode och mål som vid starten; för Both, ange båda. GUID-jämförelse används för databasplacering efter att databasidentiteten lösts upp. Läsfel eller fel placering ger FAIL, statistik måste returnera exakt en post. Completed ger PASS för request-status, CompletedWithWarning ger WARN, annat läge ger FAIL. Saknad historik ger WARN eftersom operatören kan ha tagit bort requesten; sparad completion-evidens måste då granskas.

Primary-only testar primary-placering och läsbar statistik. Arkivets aktuella databas visas som INFO och måste jämföras med baseline — scriptet gissar inte tidigare arkivplacering. Archive/Both testar explicit arkivmål och arkivstatistik. Därefter upprepas readiness-kontrollerna för tjänster, databaser, DAG, köer, DNS, certifikattillgänglighet, namespaces, connectors, events och frivilligt mail flow. HealthChecker-evidens måste fortfarande granskas separat. Under ett pågående större projekt kan andra mailboxars misslyckade requests ge miljö-FAIL även om piloten är klar.

## Manuella obligatoriska kontroller

- Outlook och OWA: inloggning, öppna/skicka/ta emot, intern och extern Autodiscover, rätt certifikat/kedja och inga oavsiktliga auth-promptar.
- Intern/extern e-post och applikationsrelä, smart hosts samt send/receive-connectorrouting och TLS.
- Arkivåtkomst, stora historiska mappar, sökning, delegation/shared mailboxes, kalender/resource-bokning, relevanta mobila klienter.
- Jämför primary/archive item counts, sizes, databasplacering, kvoter, retention/holds och behörigheter mot baseline. Aktiv användning gör att exakta antal naturligt förändras.
- Granska BadItemsEncountered/LargeItemsEncountered och CompletedWithWarning; en Completed-status ensam bevisar inte att alla objekt migrerats utan avvikelse.
- Bekräfta backup, loggtrunkering, ledigt utrymme, DAG-kopior och stabil drift efter fönstret.

Vid djupare statistikjämförelse återanvänd [Microsoft Compare-MailboxStatistics](https://microsoft.github.io/CSS-Exchange/Databases/Compare-MailboxStatistics/) efter separat granskning. Toolkit implementerar inte egen mailbox-innehållsjämförelse.

## Samlad rapport

Välj exakta CSV-filer från samma fönster och skicka dem till `New-ExchangeMigrationReport.ps1 -CsvPath`. Filerna presenteras i angiven ordning under rubriker från filnamnen. Rekommenderad ordning: Servers, Databases, InventoryCollectionStatus, MailboxInventory, MigrationReadiness, MigrationPlan, MoveStatus, PostMigrationValidation, MoveJournal. Ange miljöetikett och egen granskad HealthChecker-sammanfattning. Original-HealthChecker-rapporten ska bifogas separat.

HTML är fristående, utan externa skript eller resurser. Alla celler och texter HTML-escapas, och extern HealthChecker-HTML bäddas inte in. Sammanräkningen av WARN/Review/FAIL gäller endast de valda CSV-raderna och kan innehålla upprepade kontroller. Den är ingen övergripande hälsopoäng. Bevara scope, tidsstämplar, operatörsbeslut och underlag; export utan granskning är inte godkänd kunddokumentation.
