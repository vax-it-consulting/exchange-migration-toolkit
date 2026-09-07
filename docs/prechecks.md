# Migration readiness

Kör efter att HealthChecker granskats och innan den exakta mailbox-planen godkänns:

```powershell
$results = .\src\Test-ExchangeMigrationReadiness.ps1 -ConfigPath .\config\local.config.psd1 -HealthCheckerReportPath C:\MigrationEvidence\HealthChecker\HealthChecker.html -Html
$results | Where-Object Status -in @('WARN','FAIL') | Format-Table Check,Target,Status,Recommendation -Wrap
```

| Kontroll | PASS / INFO | WARN / FAIL och åtgärd |
| --- | --- | --- |
| HealthChecker | INFO: evidensfil finns; alltid mänsklig granskning | WARN: fil saknas. Kontrollera alla käll-/målservrar, version, datum och slutsatser |
| DatabaseMounted | PASS: konfigurerad databas hittad och mounted | FAIL: ej mounted/okänt eller query-fel. Åtgärda före plan/start |
| DatabaseCapacity | INFO: EDB-storlek, intern whitespace och EDB/loggvägar | Manuell kapacitetsbudget krävs; whitespace är inte disk free |
| Services | PASS: native Test-ServiceHealth anger required services running | FAIL: obligatoriska tjänster ej igång. WARN: kontroll kunde inte utföras |
| Version | INFO: rapporterad AdminDisplayVersion | Ingen egen supportmatris. HealthChecker och Microsofts dokumentation avgör |
| VolumeFreeSpace | PASS: läsbart fixed volume, procent fri yta över gränsen | FAIL under DiskSpaceThreshold; WARN saknade värden/anropsfel |
| Queues | PASS: under tröskel och inte Retry/Suspended | WARN: tröskel nådd, Retry/Suspended eller query-fel. Undersök trend och routing |
| CertificateAvailability | PASS: minst ett Valid-cert med privat nyckel tilldelat IIS respektive SMTP | FAIL: saknas. WARN: query-fel. SAN, faktisk bindning, utgångstid och TLS granskas separat |
| ReceiveConnector / SendConnector | INFO: Enabled är sant | WARN: disabled, tom collection eller query-fel; en avstängd connector kan vara avsiktlig |
| AutodiscoverSCP | PASS: HTTPS och förväntad AutodiscoverNamespace | WARN: saknat/avvikande SCP eller query-fel; alternativ avsiktlig design kan godkännas manuellt |
| VirtualDirectory | PASS: satt HTTPS-URL matchar PrimaryNamespace; INFO: tom URL | WARN: avvikelse/query-fel. EWS/MAPI/OWA/ECP/OAB/ActiveSync kontrolleras |
| ReachabilityFromShellHost | PASS: Test-NetConnection lyckas på konfigurerad port | FAIL: TCP misslyckas; WARN cmdlet saknas. Ingen test av hela MRS-portmatrisen |
| MailFlow | PASS: native Test-Mailflow returnerar Success; INFO: avstängd | FAIL: annat resultat, WARN query-fel. Config opt-in skickar testmeddelanden |
| EventIndicators | PASS: inga matchande Application-varningar/fel under tidsintervallet | WARN: händelser/query-fel; endast Exchange-provider, event-ID/räknare sparas, aldrig rå text |
| DAGReplication | PASS: native Test-ReplicationHealth Passed; INFO: ingen DAG | FAIL: annat native resultat; WARN query-fel/tomt. Kontrollera alla relevanta medlemmar |
| DNSFromShellHost | PASS: DNS-poster returneras för de två namespaces | FAIL: inga poster/query-fel. Förväntad IP/VIP och extern DNS behöver verifieras |
| AcceptedDomain | PASS: exakt domän finns | FAIL: saknas/query-fel; kontrollera relay-design |
| ExistingMoves | INFO: antal och separat analys | FAIL: Failed; WARN: Stalled*; query-fel FAIL. Befintlig request blockerar vald mailbox i plan/start |
| MailboxReadiness | INFO: per-mailbox-kontroll görs i plansteget | Skapa plan för exakt urval och åtgärda Review |

Resultatformat: TimestampUtc, Check, Target, Status, Severity, Detail, Recommendation. Severity är None/Informational/Medium/High för PASS/INFO/WARN/FAIL. Ej genomförd kontroll blir aldrig PASS.

## Kapacitet och scope

Win32_Volume visar även fixed volumes med mount points. Teknikern måste **mappa EdbFilePath och LogFolderPath till rätt volym** på aktiv server och relevanta DAG-kopior. Gränsen mäter procent, inte utrymme för den föreslagna flytten. En nästan tom liten disk kan ändå vara otillräcklig. Bedöm EDB-tillväxt, recoverable items, loggproduktion, loggtrunkering/backup, index och säkerhetsmarginal. Ingen automatisk kapacitets- eller go-garanti ges.

Serverlistorna behöver omfatta alla berörda aktiva servrar och DAG-kopior. Reachability/DNS körs från shellvärden; för Exchange-till-Exchange behövs separata kontroller från båda ändar. HC och dessa kontroller ersätter inte klient-, load balancer- och extern SMTP-testning.

Vanliga fel: åtkomst nekad till CIM eller eventlogg ger WARN, felstavat DB-namn ger FAIL, otillgängligt mål stoppar startens preflight, en gammal Completed move request ger Review i planen. En massmängd gamla event-ID:n kan vara bakgrundsbrus; verifiera tidsfönster och baseline. När EventMaxEvents nås är insamlingen trunkerad.

## Exit-koder

Interaktiv körning returnerar objekt utan att avsluta EMS. I en **separat** process kan `-ExitWithStatus` användas: 0 inga WARN/FAIL, 1 WARN, 2 FAIL, 3 terminerande fel. Exit 0 inkluderar INFO och utgör inte ett migrationsgodkännande. Övriga skript kastar terminerande fel; en separat `powershell.exe -File` ger då normalt exit 1.
