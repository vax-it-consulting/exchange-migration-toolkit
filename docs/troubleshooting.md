# Praktisk felsökning

Börja med `Get-MoveRequestReport.ps1 -BatchName <exakt batch>` och jämför med pre-check/baseline. Vid behov, kör `Get-MoveRequestStatistics -Identity <vald mailbox> -IncludeReport` interaktivt i skyddad miljö. Rå rapport kan innehålla känslig information. Starta inte flera omlopp av samma mailbox för att försöka lösa ett problem.

| Symtom | Nästa kontroll | Operativ åtgärd |
| --- | --- | --- |
| StalledDueToTarget* | StatusDetail, målvolym/EDB/loggar, MRS-belastning, köer och DAG | Ett stall kan vara tillfällig resursreglering. Följ trend; minska nya starter, utred målresursen |
| StalledDueToSource* | Källans disk, CPU/I/O, services, databaskopia och nätväg | Kontrollera HealthChecker och lagring. Tvinga inte förbi workload-skydd |
| Failed | FailureType, Message och native IncludeReport | Stoppa nya batchar vid gemensam orsak. Åtgärda och återuppta endast vald request efter beslut |
| Diskutrymme | Win32_Volume plus EdbFilePath/LogFolderPath, mount points, alla relevanta kopior | Utöka kapacitet eller minska batch. PASS i procent är inte utrymmesbudget |
| Växande transaktionsloggar | Backup, truncation, kopioreplikering, checkpoint/loggvolym | Stoppa ny belastning. Radera aldrig Exchange-loggar manuellt och ändra inte circular logging slentrianmässigt |
| Mail queues | Get-Queue, Retry/Suspended, routing och smart host/DNS | Jämför över tid, utred native LastError lokalt. Radera inte kömeddelanden som ”fix” |
| Certifikat | HealthChecker samt IIS/SMTP-bindning, SAN, kedja, NotAfter, privat nyckel | Säkerställ förväntat certifikat på Exchange/load balancer; planera certifikatbyte separat |
| DNS | Resolve-DnsName från klient, varje server och extern testpunkt | Kontrollera split DNS, VIP, TTL och brandvägg, inte bara att ett namn svarar |
| Autodiscover | SCP, DNS, HTTPS-svar, Outlook-test och faktisk certifikatbindning | Kontrollera avsedd namespace-design; ändra inte interna servernamn för att lösa klientnamespace |
| Connector-fel | Address spaces, source servers, smart host, bindings, remote ranges, permissions, TLS | Jämför med inventory och testa faktisk SMTP. Undvik öppet relay |
| Arkivproblem | ArchiveGuid, ArchiveDatabase, RemoteRecipientType, separat arkivstatistik och klientåtkomst | Remote/cloud archive kräver separat workflow. PrimaryOnly flyttar inte arkivet eller filtrerar primär historik |
| Existing move request | Get-MoveRequest och dess statistik/history | Granska även Completed. Spara evidens; välj explicit resume/cancel/cleanup, aldrig automatisk overwrite |
| Large/Bad items | Antal, failure details, kvarvarande data, hold/retention och verksamhetskrav | Toolkit sätter inte BadItemLimit/LargeItemLimit/AcceptLargeDataLoss. Dataförlust kräver separat dokumenterat beslut |
| Readiness WARN: access/cmdlet | RBAC, EMS, CIM/WinRM, eventlogg-rättigheter | Kör native kontroll interaktivt. Saknad kontroll är inte frisk status |
| Startfel efter skapad request | Exchange-status och MoveJournal-filer | Request kan ha skapats före export/loggfel. Återställ journaling/behörighet; välj endast ännu ej startade identiteter |
| Alla parametrar ser rätt ut, inga moves | No Migration eller Review-rader, WhatIf, operatörsbekräftelse | Granska planen. WhatIf skapar avsiktligt inget och befintlig request blockerar starten |

För generella serverproblem kör [HealthChecker](microsoft-tools.md), för setup [SetupAssist/SetupLogReviewer](microsoft-tools.md), och för incidentunderlag [ExchangeLogCollector](https://microsoft.github.io/CSS-Exchange/Diagnostics/ExchangeLogCollector/). Ingen av dessa hämtas/körs automatiskt. Läs alltid aktuell verktygsdokumentation innan en separat åtgärd.

Eskalera när återkommande stalls/failed påverkar klienter, det finns dataförlustindikatorer, loggvolym hotas eller rollback/återställningens konsekvenser är oklara. Spara status, tidslinje, exakt komponent/mål och redan vidtagna åtgärder.
