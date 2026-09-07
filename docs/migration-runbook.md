# Runbook för migreringsfönster

Kopiera denna mall till kundens skyddade ärende, inte till en versionshanterad kundfil. Fyll i ändrings-ID, datum/tidszon, tekniker, beslutsfattare, kontaktväg, käll-/målservrar, databas-/arkivmål, batchnamn, mailboxurval, stoppgränser och senaste tid för completion/stop-beslut.

## Before migration

- [ ] Versions-/coexistensmatris och migreringsväg verifierad mot aktuella Microsoft-källor.
- [ ] Godkända backup- och dokumenterade återställningsrutiner; återläsningsmöjlighet verifierad.
- [ ] Berörda verksamheter informerade enligt uppdragets rutin.
- [ ] Skyddade config/output/loggmappar, åtkomst och retention klara.
- [ ] Repo-commit, tester i utvecklingsmiljö och godkänd Exchange-labbpilot noterade.
- [ ] Inventory inklusive separat primary/archive, collection-status, systemberoenden och connectors sparat.
- [ ] Lokala arkiv som lämnas kvar har en stödd drift- och avvecklingsplan.
- [ ] HealthChecker-filens källa/version/hash/signatur och operatörsgranskning dokumenterade.

## Pre-check

- [ ] HealthChecker körd på alla berörda servrar och resultaten granskade.
- [ ] Test-ExchangeMigrationReadiness körd med aktuell målconfig och HC-evidens.
- [ ] FAIL åtgärdade; WARN/INFO har uttryckliga bedömningar och ansvarig.
- [ ] EDB/loggvolymer inklusive mount points och DAG-kopior har tillräcklig budget för vald payload och overhead.
- [ ] Mail flow, queues, DNS, klientnamespaces och certifikat verifierade från rätt testpunkter.
- [ ] New-ExchangeMigrationPlan körd för exakt mailboxlista, mode och mål; inga olösta Review.
- [ ] Stoppgränser för disk/loggar, klientpåverkan och request-fel fastställda.

## Pilot

- [ ] Representativ liten pilot vald (inklusive relevanta shared/resource/arkivfall i separata grupper).
- [ ] Start-MailboxMigration -WhatIf granskad; kompletterande native WhatIf vid behov.
- [ ] Pilot startad med standardpaus, batch-ID och MoveJournal sparade.
- [ ] Klient/mail flow stabilt under kopiering och före cutover.
- [ ] Pilot slutförd enligt Completion, validerad och godkänd innan större batchar.

## Migration batch

- [ ] Varje batch har uttrycklig identitetslista och enhetlig mode/måldatabas.
- [ ] Preflight gjord igen av startscriptet; review-tabell kontrollerad.
- [ ] Start genomförd; antal skapade/journalförda requests jämfört med plan.
- [ ] Vid partiellt startfel: stoppa, inventera redan skapade requests och upprätta nytt urval.
- [ ] Inga gamla requests raderade automatiskt; inga data-loss-parametrar införda utan separat beslut.

## Monitoring

- [ ] Get-MoveRequestReport körs återkommande; rapportfiler med tidsstämplar sparas.
- [ ] Progress, StatusDetail, failures och skipped/bad/large items granskas.
- [ ] Disk/loggar, backuptrunkering, kopior, mail queues och klientpåverkan följs.
- [ ] Vid stoppgräns: inga nya starter; vald pågående request pausas om lämpligt.

## Completion

- [ ] Batchens exakta identiteter och förväntade AutoSuspended-status verifierade.
- [ ] Godkänt completion-fönster och beslutstid dokumenterade.
- [ ] Per vald request: Set-MoveRequest -SuspendWhenReadyToComplete:$false och Resume-MoveRequest enligt migrationsguiden.
- [ ] Ingen oavsiktlig framtida CompleteAfter begränsar det valda läget.
- [ ] Completed/CompletedWithWarning och faktiska mål verifierade; avvikelser utredda.

## Validation

- [ ] Test-PostMigration körd med samma mode/mål och explicit lista.
- [ ] Ny inventory jämförd mot baseline; primary och archive bedöms separat.
- [ ] Outlook/OWA, Autodiscover, arkiv, delegation, kalender och relevanta resurser testade.
- [ ] Intern/extern e-post, applikationsrelä, TLS och namespaces testade.
- [ ] Backup, loggar, DAG och kvarvarande källberoenden verifierade.
- [ ] Verksamhets-/teknisk sign-off dokumenterad.

## Rollback decision

- [ ] Aktuell request-status och verklig aktiv mailboxplacering fastställda.
- [ ] Se [rollback-plan](rollback-plan.md): särskilj paus/avbruten kopiering från reverse move/restore efter completion.
- [ ] Genomförbarhet, support, kapacitet, tid och datakonsekvenser godkända av ansvarig.
- [ ] Ingen felaktig utfästelse om snabb/automatisk rollback.

## Cleanup

- [ ] Completion-evidens, MoveJournal, inventory och felrapporter arkiverade före request-cleanup.
- [ ] Eventuell Remove-MoveRequest gäller endast namngiven granskad request efter separat beslut.
- [ ] Ingen databas/server avvecklas med kvarvarande primary, archive, system/public-folder/hybrid/connector-beroenden.
- [ ] Tillfälliga rättigheter och data hanteras enligt retention; inga kunddata committas.

## Documentation

- [ ] New-ExchangeMigrationReport bygger HTML från explicit valda rapporter från rätt fönster.
- [ ] Original-HealthChecker, scope/version/hash, tidslinje, go/stop-beslut och manuella tester bifogade.
- [ ] Kvarstående risker, arkivfas och uppföljningsägare noterade.
- [ ] Ändringsärendet avslutat först efter överenskommen stabilitetsperiod.
