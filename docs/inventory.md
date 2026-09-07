# Inventory och primary/archive-analys

`Get-ExchangeInventory.ps1` läser Exchange; ingen mailbox flyttas. Mailbox-tabellen omfattar lokala UserMailbox, SharedMailbox, RoomMailbox och EquipmentMailbox via `Get-Mailbox -ResultSize Unlimited`. Statistik hämtas per mailbox med `Get-MailboxStatistics`, och separat med `-Archive` för ett lokalt arkiv.

```powershell
$rows = .\src\Get-ExchangeInventory.ps1 -ConfigPath .\config\local.config.psd1 -IncludeDisconnected -Html -Verbose
$rows | Where-Object ArchiveEnabled | Sort-Object ArchiveBytes -Descending |
    Select-Object DisplayName,MailboxType,PrimaryDatabase,PrimaryBytes,ArchiveDatabase,ArchiveBytes,TotalBytes,TargetDatabase,MigrationAction
```

| Fältgrupp | Betydelse |
| --- | --- |
| DisplayName, PrimarySmtpAddress, Identity, MailboxType | Namn, adress, stabil ExchangeGuid och mailbox-typ |
| PrimaryDatabase/Server/Size/Bytes/ItemCount | Aktiv primary-data och statistikens server; inte en garanti om framtida DAG-aktiv kopia |
| ArchiveEnabled/Status/Database/Server/Size/Bytes/ItemCount | Egen arkivkomponent; tom lokal DB kan betyda ett fjärrarkiv som måste granskas |
| TotalBytes | Summa endast när båda nödvändiga bytevärdena är kända |
| PrimaryDeletedItemSize, ArchiveDeletedItemSize | Separat indikation om recoverable/deleted data; ingår inte i planens payload |
| Quotas och UseDatabaseQuotaDefaults | Mailbox-inställningar; vid DB-defaults måste effektiv primary-kvot läsas från Databases-rapporten |
| TargetDatabase, ArchiveTargetDatabase | Kandidater från config, inte beslut |
| MigrationAction | Alltid Review i inventory; beslut tas först i uttrycklig plan |
| CollectionStatus/Notes | Saknad statistik eller oklart arkiv; okänd storlek visas tom |

Syntetiskt exempel (avrundade GiB enbart för läsbarhet):

| User | Typ | Primary DB | Primary GiB | Archive DB | Archive GiB | Target | Action |
| --- | --- | --- | ---: | --- | ---: | --- | --- |
| Pilot | UserMailbox | DB-Source-01 | 24 | DB-Archive-Source | 780 | DB-Target-01 | Review |
| Support | SharedMailbox | DB-Source-01 | 12 | — | 0 | DB-Target-01 | Review |

Övriga CSV/HTML: servrar/build, databaser och EDB/loggvägar/kvoter, DAG och kopior, accepted domains, send/receive connectors, certifikatmetadata, OWA/ECP/EWS/MAPI/ActiveSync/OAB/Autodiscover/PowerShell virtual directories, SCP, Outlook Anywhere och befintliga moves. Server- och databasdetaljer följer config-scope; domains/send connectors/DAG-listan är organisationsdata. Valfri disconnected-statistik visar bland annat Disabled och SoftDeleted där cmdleten tillåter det; den ändrar eller reconnectar inget.

Läs alltid `InventoryCollectionStatus`. Saknad cmdlet/RBAC ger WARN för den aktuella samlingen. En samling som misslyckas mitt i en serverslinga exporteras inte som fullständig; kör om den efter åtgärd. Bortfall av huvudlistan mailboxar är ett terminerande fel. Statistik per mailbox kan vara partiell och märks då i mailbox-raden.

## Planera stora arkiv separat

1. Granska exakt primary/arkiv-placering, licensiering, retention/holds och backupansvar.
2. Planera aktiv primary-data med `Mode Primary` och migrera endast godkänd selektion. PrimaryOnly filtrerar **inte** äldre meddelanden i primary-mailboxen.
3. Lämna lokalt arkiv tillfälligt endast om den kvarvarande miljön och kombinationen av versioner stöds, arkivåtkomst fungerar och livscykel/avvecklingsplan tillåter det.
4. Validera primary samt fortsatt åtkomst till arkivet. Planera senare `Mode Archive` med egen arkivdatabas och egen kapacitetsbedömning.
5. Avveckla aldrig en server/databas med kvarvarande arkiv eller andra beroenden. Att flytta primary innebär inte att arkivet blivit fristående historisk lagring.

Bytekonvertering använder exakt ToBytes-värde eller ett uttryckligt byteantal från deserialiserad statistik. Enbart ett avrundat MB/GB-värde gissas inte. Arkiv i Exchange Online och otydliga fjärrarkiv kräver separat arbetsflöde. [Microsofts New-MoveRequest](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-moverequest?view=exchange-ps) beskriver komponentvalen. Jämför resultat efter flytt med nytt inventory och vid behov [CSS-Exchange Compare-MailboxStatistics](https://microsoft.github.io/CSS-Exchange/Databases/Compare-MailboxStatistics/).
