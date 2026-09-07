# Verifieringsrapport — 2026-09-07

Status: **initial implementation; runtime- och Exchange-gates återstår**. Ingen mailbox eller produktionsmiljö har kontaktats. Definition of Done punkt 11 (grön offline-testsvit i Astra) är inte uppfylld, och uppmätt funktion i riktig Exchange är inte etablerad.

| Kontroll | Faktiskt resultat |
| --- | --- |
| Native PowerShell syntax, via tests/Invoke-Tests.ps1 | BLOCKERAD: `pwsh` saknas; processförsök gav exit 127 |
| Pester 5.7.1, separat försök | BLOCKERAD: `pwsh` saknas; exit 127. Inga Pester-testfall körda |
| Smoke via Windows PowerShell | BLOCKERAD: `powershell.exe` saknas; exit 127. Inga PowerShell smoke-testfall körda |
| Hämtning av PowerShell | Kunde inte genomföras under miljöns nätverksbegränsning; inga skydd kringgicks |
| Offline syntetiskt workflow | Implementerat men EJ KÖRT; kräver en tillgänglig PowerShell-process |
| Windows PowerShell 5.1 / EMS | EJ KÖRT |
| Exchange 2019/SE, MRS, arkiv, DAG, klienter | EJ KÖRT; separat labbgate i tests/README.md |
| HealthChecker | Officiell dokumentation granskad; ingen binär/release hämtad eller körd |
| Statisk lokal granskning | Se körda resultat nedan; ersätter inte native syntax eller tester |

## Testsvit som medföljer

Pester testar config, selektion/CSV, rapportskydd, storlekar, result severity, mockad inventory/plan och readiness. Fristående smoke testar rapportexport och native syntax. Syntetiskt workflow testar riktiga entrypoints för inventory, plan, WhatIf, start, dubblettskydd, monitoring och kundrapport med test-cmdlets. Antalet godkända runtime-testfall i denna miljö är **0**, eftersom ingen PowerShell-runtime kunde startas; detta betyder ej körda, inte ett konstaterat kodtestfel.

## Krav före första produktion

1. Kör `tests/Invoke-Tests.ps1` i en ny PowerShell-process med Pester 5.7.1; åtgärda varje syntax-/runtime-/testfel.
2. Kör på Windows PowerShell 5.1 och genomför hela Exchange-labbchecklistan i tests/README.md.
3. Validera actual native property shapes, deserialiserade bytevärden, GUID-uppslag, RBAC, archive modes, completion-parametrar och fel efter partiell start.
4. Granska kundens HealthChecker-evidens, supportmatrix, backup, capacity och pilotresultat innan go-beslut.

Det är avsiktligt att leveransen inte beskriver blockerade tester som passerade. Första commit är en reviewbar initial kodbas, inte en verifierad produktionsrelease.

## Körda statiska kontroller

- PASS: lexical delimiter/string/comment balance in 15 PowerShell files (not native syntax validation)
- PASS: 24 local Markdown links resolve
- PASS: 31 documented toolkit command lines use existing scripts/declared named parameters
- PASS: 14 sensitive path patterns ignored; 4 source/example/placeholder paths preserved
- PASS: every public script has PowerShell version requirement, StrictMode, CmdletBinding and help
- PASS: static scan found no customer identifiers, private IP examples, recognizable secret tokens or runtime download/evaluation

Granskningen kördes med lokal Python/Git och en enkel lexikal kontroll. Den kan hitta obalanserade strängar/kommentarer/delimiters men är inte en PowerShell-parser. Secret-sökningen är ett lättviktigt mönstertest och manuell kodgranskning, ingen garanti mot alla former av data i Git.
