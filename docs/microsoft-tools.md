# Microsoft-verktyg och externa beroenden

## Ansvarsfördelning

| Behov | Återanvändning | Integration |
| --- | --- | --- |
| Build, kända problem, TLS, .NET, OS, CVE och generell health | [Microsoft CSS-Exchange HealthChecker](https://microsoft.github.io/CSS-Exchange/Diagnostics/HealthChecker/) | Obligatoriskt operatörssteg före go-beslut; rapportreferens till readiness och granskad sammanfattning till kundrapport |
| Flytta och följa mailboxar | Native Exchange EMS cmdlets | Tunna PowerShell-wrappers; ingen egen flyttmotor |
| DAG/service/mail flow | Test-ReplicationHealth, Test-ServiceHealth, Test-Mailflow | Befintliga cmdlets med enhetliga resultat; inga egna Exchange health-regler |
| Djup jämförelse av mailbox-statistik | [Compare-MailboxStatistics](https://microsoft.github.io/CSS-Exchange/Databases/Compare-MailboxStatistics/) | Valfri manuell fördjupning efter pilot; inte automatisk |
| Exchange-installationsproblem | [SetupAssist](https://microsoft.github.io/CSS-Exchange/Setup/SetupAssist/), [SetupLogReviewer](https://microsoft.github.io/CSS-Exchange/Setup/SetupLogReviewer/) | Hänvisning vid setup-fel, utanför mailbox-migreringsflödet |
| Incidentloggar | [ExchangeLogCollector](https://microsoft.github.io/CSS-Exchange/Diagnostics/ExchangeLogCollector/) | Manuellt, skyddat incidentunderlag; ersätter egen logginsamlare |

CSS-Exchange utvärderades som primär verktygskälla. Toolkit distribuerar inte dess kod, försöker inte tolka dess interna XML-schema och uppdaterar inte verktyg automatiskt. Samlad HTML använder en uttryckligt operatörsskriven HealthChecker-sammanfattning. Originalrapporten bifogas separat; filens existens utgör inte health-godkännande.

## Skaffa och verifiera HealthChecker

1. Gå manuellt till [Microsofts officiella repository](https://github.com/microsoft/CSS-Exchange) och release-länken i HealthChecker-dokumentationen. Hämta **release-skriptet**, inte en enskild ofullständig byggfil ur källträdet.
2. Använd senaste av organisationen granskade release vid uppdragets start. Frys samma granskade fil under migreringsfönstret. Ingen numerisk release rekommenderas som permanent säker; security-regler ändras. Dokumentationskontroll: 2026-09-07. Ingen release har körts/verifierats i levererande Astra.
3. Spara verktyget utanför repot, t.ex. `C:\Tools\CSS-Exchange`. Kontrollera URL/utgivare, Authenticode och beräkna SHA-256. Jämför hash med separat betrodd publicerad checksumma om sådan finns. En självberäknad hash identifierar filen men bevisar inte dess ursprung.
4. Registrera hämtningstid, release/version, käll-URL, SHA-256, signaturstatus och granskare i ändringsärendet. Vid saknad/ogiltig signatur följs organisationens kodgodkännandeprocess innan körning. Använd aldrig `iex` på en nätverksrespons.

```powershell
$healthScript = 'C:\Tools\CSS-Exchange\HealthChecker.ps1'
Get-AuthenticodeSignature -FilePath $healthScript | Format-List Status,StatusMessage,SignerCertificate
Get-FileHash -LiteralPath $healthScript -Algorithm SHA256
```

Kör i upphöjd EMS på Exchange-server enligt HealthCheckers aktuella behörighetskrav: lokal administratör och Organization Management. Domain Admins behövs enligt Microsoft bara för DCCoreRatio-alternativet, som detta arbetsflöde inte använder. [Krav och syntax](https://microsoft.github.io/CSS-Exchange/Diagnostics/HealthChecker/).

## Kör och samla evidens

Efter godkänd filgranskning, från repo-roten:

```powershell
$config = Import-PowerShellDataFile .\config\local.config.psd1
$healthOutput = 'C:\MigrationEvidence\HealthChecker'
New-Item -ItemType Directory -Path $healthOutput -Force
$servers = @($config.SourceExchangeServers + $config.TargetExchangeServers | Select-Object -Unique)
& $healthScript -Server $servers -OutputFilePath $healthOutput -SkipVersionCheck
& $healthScript -BuildHtmlServersReport -XMLDirectoryPath $healthOutput -HtmlReportFile 'HealthChecker.html' -OutputFilePath $healthOutput -SkipVersionCheck
```

`-SkipVersionCheck` används för att undvika verktygets versionskontroll under det frysta körfönstret. Kontrollera exakt beteende mot den granskade releasen. Output kan innehålla känslig information. Läs rapporten för samtliga servrar och fastställ exakt genererad HTML-sökväg.

```powershell
$healthReport = Read-Host 'Exakt sökväg till den granskade rapporten'
.\src\Test-ExchangeMigrationReadiness.ps1 -ConfigPath .\config\local.config.psd1 -HealthCheckerReportPath $healthReport -Html
```

Utan HealthChecker fungerar inventory, plan, start, monitorering, migration checks och rapportering tekniskt; readiness visar WARN för saknad evidens. De egna build-raderna är INFO, ingen support-/CVE-bedömning. `CertificateExpiryWarningDays` i config är en dokumenterad **manuell granskningsgräns**, inte ett filter eller en override av HealthChecker. Toolkit kontrollerar bara tillgängliga IIS/SMTP-certifikat; HealthChecker äger expiry/TLS-logiken.

## Testberoende

Enhetstester kräver Pester **5.7.1**, som är repots fasta testberoende, inte en utfästelse om senaste version. [Officiellt Pester-projekt](https://github.com/pester/Pester). Installera endast efter eget initiativ på utvecklings-/testmaskinen:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Repository PSGallery
```

Cmdleten kan fråga om repository/provider-förtroende; följ lokala regler. Toolkit installerar inget. Fristående smoke tests kräver bara PowerShell; riktiga Exchange-anrop är ett separat labbgate.
