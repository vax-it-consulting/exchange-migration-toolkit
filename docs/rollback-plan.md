# Stopp-, återstarts- och återställningsplan

En completed mailbox move kan inte generellt ”rullas tillbaka” genom att radera en request. Skilj mellan att avbryta en **ännu inte slutförd kopiering**, att göra en **ny flytt i motsatt riktning** och att genomföra **backupbaserad återställning**. Välj åtgärd utifrån faktisk status, support, åtkomst och datakonsekvenser.

## När ska man stoppa?

Stoppa nya starter vid hotad EDB/loggkapacitet, klientpåverkan, återkommande gemensamma move-fel, dataförlustindikatorer, instabil DAG/lagring eller när fönstret inte medger säker completion. Pausa berörda requests där tillståndet tillåter det. Kontakta beslutsfattaren enligt runbook. Fortsätt bara om orsaken är förstådd, resurser och klientfunktion är stabila och kvarvarande risk uttryckligen accepterats. Ett kort isolerat stall kan vara normal reglering men ska bedömas mot trend, inte namnet ensamt.

## Incomplete och suspended moves

Vid kopiering före completion är källmailboxen normalt den aktiva. **Verifiera detta**, aktuell status och klientåtkomst innan ett avbrott beslutas; anta inte att samma sak gäller när CompletionInProgress redan börjat. En suspended/AutoSuspended request kan ofta återupptas efter att orsaken rättats. Standardpausen i toolkit måste uttryckligen hävas för cutover enligt migrationsguiden.

```powershell
Get-Mailbox -Identity 'pilot@example.test' | Format-List ExchangeGuid,Database,ArchiveDatabase
Get-MoveRequest -Identity 'pilot@example.test' | Get-MoveRequestStatistics |
    Format-List Status,StatusDetail,PercentComplete,SourceDatabase,TargetDatabase,Message
Suspend-MoveRequest -Identity 'pilot@example.test' -Confirm
```

En request i CompletionInProgress kan inte behandlas som en vanlig kopieringspaus. Bedöm om completion ska tillåtas avslutas och felsök därefter; använd Microsoft Support vid oklart tillstånd. Rensa inte manuellt AD-attribut, request-queue-poster, EDB- eller loggfiler.

## Avbryt en request

Spara evidens, fastställ tillstånd och aktiv mailbox, dokumentera beslut och kontrollera cmdletens WhatIf:

```powershell
Remove-MoveRequest -Identity 'pilot@example.test' -WhatIf
# Endast efter godkänt beslut:
Remove-MoveRequest -Identity 'pilot@example.test' -Confirm
```

[Microsoft Remove-MoveRequest](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/remove-moverequest?view=exchange-ps) är åtgärden för att avbryta en request. Verktyget anropar den aldrig automatiskt. Efter borttagning verifieras mailboxåtkomst, placering och kapacitet. Underlag i requesthistoriken kan försvinna, därför ska rapporter sparas först. Gör inte breda pipelines som tar bort alla requests.

## Efter completed move

Att ta bort en completed request flyttar **inte** mailboxen tillbaka. En eventuell ny flytt till en tidigare databas är en ny migrationsåtgärd med egen pre-check, kapacitetsbudget, completion och risk. Kontrollera om versioner/riktning och samexistens överhuvudtaget stöds vid den aktuella tidpunkten; anta inte att en SE-till-2019-retur är en tillåten återställningsväg. Den gamla källan kanske inte längre är tillgänglig eller supportad.

En gammal soft-deleted källkopia är inte en generell live-backup och innehåller inte nödvändigtvis ändringar efter completion. Reconnect/restore kräver särskild plan för identitet, nya meddelanden, retention/holds, dubbletter och verksamhetens RPO/RTO. Toolkit erbjuder inte detta automatiskt.

## Innan reverse move eller restore

- Verifiera aktiv primary- **och** archive-databas separat samt aktuell klientåtkomst.
- Spara requeststatistik/journal och fastställ senaste säkra checkpoint.
- Bedöm efterföljande ändringar i mailboxen, backupens återställningspunkt och dataförlustrisk.
- Kontrollera versionssupport, målresurser, nätvägar, backup/restore-test och tidsåtgång.
- Utse beslutsfattare och återställningsansvarig; dokumentera acceptans och verifieringsplan.

Backup ska finnas enligt en dokumenterad och övad Exchange-medveten återställningsstrategi före migrering. DAG-replikering ersätter inte denna plan. Serveruppgradering, avinstallation och återställning av OS/Exchange är egna processer; de blir inte reversibla bara för att en mailbox move kan pausas.
