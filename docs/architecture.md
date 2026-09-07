# Arkitektur och begränsningar

Sju operatörsskript använder native EMS. Tre små interna `.psm1`-filer delar config/logg/export, mailboxdatainsamling/planering och readiness-kontroller. De är interna hjälpmoduler, inte en publik installerbar Exchange-ersättare. `Invoke-EMTCommand` är en enda tunn felhanterings-/mockgräns som anropar det givna kommandot med ErrorAction Stop; ingen session, credential eller egen Exchange-klient byggs.

Separera alltid health (HealthChecker) från readiness (valda mål och mailboxar). Inventerat AdminDisplayVersion är en observation, ingen supportbedömning. Inga egna TLS/CVE/.NET/OS/build-regler underhålls. HealthChecker är dokumenterat operatörssteg, inte en maskintolkad eller automatiskt godkänd dependency.

## Konfiguration

`Import-PowerShellDataFile` används i stället för dot-sourcing. Obligatoriska nycklar, typer och rimliga gränser valideras. Inga kundidentiteter finns i kod. OutputPath/LogPath kan vara absoluta; relativa utgår från repo-roten. Mailboxurval är obligatoriska parametrar för plan/start/post. Inventory är organisationsomfattande för stödda lokala mailbox-typer; databas-/serversamlingar följer config.

DiskSpaceThreshold är procent fri fixed-volume-yta, inte en migration-payload-validering. CertificateExpiryWarningDays är operatörens manuella granskningsgräns gentemot HealthChecker/certifikatevidens och används inte som egen health-regel. EventLookbackHours/EventMaxEvents och QueueMessageCount styr migrationsspecifika observationer.

## Fel- och skrivmodell

Läsfel för mål/requestlista/mailboxurval stoppar plan/start. Övriga readiness-anropsfel märks WARN/FAIL enligt kontrollens betydelse. Saknat värde är aldrig noll eller PASS. Planen blockerar Review före första New-MoveRequest. Ändringar är seriella och avbryts vid första fel; operationen är **inte atomisk** och tidigare requests ligger kvar. Exchange ger sista skyddet mot en parallellt skapad dubblett.

ShouldProcess omger varje New-MoveRequest. WhatIf orsakar inga Exchange- eller filskrivningar i startscriptet men gör läsanrop. Inventory/plan/report är läsande mot Exchange och skriver avsiktligt lokala rapporter. EnableMailFlowTest är explicit opt-in till native testmeddelanden.

Loggar innehåller fasta eventkoder, inga identiteter/råa feltexter. MoveJournal innehåller identiteter i skyddad output och sparas per lyckad request. Om logg/export misslyckas efter New-MoveRequest kan Exchange ha skapad request utan full journal. Kontrollera då Exchange innan återstart. CSV-celler skyddas mot formelinledning och HTML escapas. Detta ersätter inte åtkomstskydd och klassning.

## Praktiska avgränsningar

- Produktion kräver Windows PowerShell 5.1/EMS. Native remoting-objekt, RBAC, arkivkombinationer och exakta cmdletparametrar måste labbtestas.
- Samma organisation/forest, lokala User/Shared/Room/Equipment-mailboxar. Inget hybrid/cross-forest/public-folder/system-mailbox-flöde.
- Ingen concurrency-controller, automatisk retry/completion/cleanup, request overwrite eller data-loss-parameter.
- Both kräver lokalt arkiv på varje vald mailbox; blanda inte mailboxar utan arkiv i samma Both-batch.
- Primary-target valideras även i Archive-läge. Config ska ange en giltig mounted primary-kontext.
- Plan beskriver logisk datamängd; ingen komplett kapacitetsberäkning eller tidsprognos. Recoverable items och loggar granskas separat.
- Databasserver från mailbox-statistik är ögonblicksdata; DAG kan växla aktiv kopia.
- Namespace/DNS/certifikattillgänglighet är grundkontroller; faktisk TLS-kedja, VIP-bindning, Autodiscover-svar och klientfunktion kräver manuella tester.
- General health-evidens ålders-/innehållsvalideras inte automatiskt. Ett bifogat filnamn ger bara INFO.
- Samlad rapport importerar explicit valda CSV-filer; ingen automatisk korrelation mellan flera tidsfönster och ingen HealthChecker-HTML-embedding.

## Nästa förbättringar efter grön labbgate

1. Kör och justera tester på PowerShell 5.1 + riktig Exchange 2019/SE med lokala arkiv och DAG.
2. Lägg därefter till CI för syntax/Pester, PSScriptAnalyzer och kodsignering enligt organisationens policy.
3. Utöka planering med explicit komponentvis beslut/manifest och evidensfingeravtryck om verkliga uppdrag behöver blandade actions.
4. Överväg validerad EDB/loggvolymmappning och projektspecifik kapacitetsbudget; återanvänd Microsofts underlag.
5. Publicera som versionerad PowerShell-modul först när gränssnitt och labbresultat är stabila.
