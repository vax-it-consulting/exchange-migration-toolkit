#requires -Version 5.1
<#
.SYNOPSIS
Validate and start explicitly selected local mailbox moves, pausing completion by default.
.DESCRIPTION
The complete list is preflighted before the first write. Stops on the first execution
failure; earlier requests remain in place. Never removes/replaces existing requests.
WhatIf performs read-only preflight and creates no requests or report/log files.
.PARAMETER PrimaryOnly
Move only primary data (also the default when neither component switch is supplied).
.PARAMETER ArchiveOnly
Move only local archive data to ArchiveTargetDatabase.
.PARAMETER IncludeArchive
Move primary and local archive data together; mutually exclusive with component switches.
.PARAMETER CompletionMode
Suspend (default), Automatic, or Scheduled. Scheduled requires CompleteAfter.
.PARAMETER SuspendWhenReadyToComplete
Explicit alias for CompletionMode Suspend. Cannot be combined with another completion mode.
.EXAMPLE
.\src\Start-MailboxMigration.ps1 -ConfigPath .\config\local.config.psd1 -Identity pilot@example.test -BatchName Pilot-01 -PrimaryOnly -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High',DefaultParameterSetName='Identity')]
param([Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory,ParameterSetName='Identity')][ValidateNotNullOrEmpty()][string[]]$Identity,
    [Parameter(Mandatory,ParameterSetName='Csv')][ValidateNotNullOrEmpty()][string]$CsvPath,
    [string]$TargetDatabase, [string]$ArchiveTargetDatabase,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$')][string]$BatchName,
    [switch]$PrimaryOnly, [switch]$ArchiveOnly, [switch]$IncludeArchive,
    [ValidateSet('Suspend','Automatic','Scheduled')][string]$CompletionMode = 'Suspend',
    [datetime]$CompleteAfter, [switch]$SuspendWhenReadyToComplete)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Data.psm1')
if (([int]$PrimaryOnly.IsPresent + [int]$ArchiveOnly.IsPresent + [int]$IncludeArchive.IsPresent) -gt 1) { throw 'Choose only one component switch.' }
if ($SuspendWhenReadyToComplete -and $CompletionMode -ne 'Suspend') { throw 'Conflicting completion options.' }
if ($CompletionMode -eq 'Scheduled') {
    if (-not $PSBoundParameters.ContainsKey('CompleteAfter') -or $CompleteAfter -le (Get-Date)) { throw 'Scheduled completion requires a future CompleteAfter.' }
} elseif ($PSBoundParameters.ContainsKey('CompleteAfter')) { throw 'CompleteAfter requires CompletionMode Scheduled.' }
$config = Read-EMTConfig $ConfigPath
if (-not $TargetDatabase) { $TargetDatabase = $config.TargetDatabase }
if (-not $ArchiveTargetDatabase) { $ArchiveTargetDatabase = $config.ArchiveTargetDatabase }
$mode = if ($ArchiveOnly) { 'Archive' } elseif ($IncludeArchive) { 'Both' } else { 'Primary' }
$ids = @(Resolve-EMTMailboxList -Identity $Identity -CsvPath $CsvPath)
$plan = @(Get-EMTPlan $ids $TargetDatabase $ArchiveTargetDatabase $mode)
$plan | Select-Object Identity,PrimarySmtpAddress,MigrationAction,TargetDatabase,ArchiveTargetDatabase,EstimatedPayloadBytes,PlanReason | Format-Table -AutoSize | Out-Host
if (@($plan | Where-Object MigrationAction -eq 'Review').Count) { throw 'Preflight blocked the batch. Resolve every Review row before retrying.' }
$pending = @($plan | Where-Object { $_.MigrationAction -like 'Move *' })
if ($pending.Count -eq 0) { Write-Information 'No migration needed.' -InformationAction Continue; return }
# Validate write-cmdlet availability before any side effects.
$null = Get-Command New-MoveRequest -ErrorAction Stop
if (-not $WhatIfPreference) { Write-EMTLog $config -Event MIGRATION_PREFLIGHT_PASSED -Count $pending.Count }
foreach ($row in $pending) {
    $arguments = @{ Identity = $row.Identity; BatchName = $BatchName }
    if ($mode -ne 'Archive') { $arguments.TargetDatabase = $row.TargetDatabase }
    if ($mode -ne 'Primary') { $arguments.ArchiveTargetDatabase = $row.ArchiveTargetDatabase }
    if ($mode -eq 'Primary') { $arguments.PrimaryOnly = $true }
    if ($mode -eq 'Archive') { $arguments.ArchiveOnly = $true }
    switch ($CompletionMode) {
        Suspend { $arguments.SuspendWhenReadyToComplete = $true }
        Scheduled { $arguments.CompleteAfter = $CompleteAfter }
    }
    if ($PSCmdlet.ShouldProcess($row.PrimarySmtpAddress, "Create $mode move to primary=$($row.TargetDatabase), archive=$($row.ArchiveTargetDatabase), batch=$BatchName, completion=$CompletionMode")) {
        try {
            # Exchange enforces uniqueness again, closing the race after our preflight.
            $null = Invoke-EMTCommand New-MoveRequest $arguments
            Write-EMTLog $config -Event MOVE_CREATED -Count 1
            # Per-request journal persists immediately, even if a later request fails.
            # Contains mailbox identity, so it belongs in the protected output directory.
            $journal = [pscustomobject]@{ TimestampUtc = [datetime]::UtcNow.ToString('o'); Identity = $row.Identity; PrimarySmtpAddress = $row.PrimarySmtpAddress; BatchName = $BatchName; Mode = $mode; TargetDatabase = $row.TargetDatabase; ArchiveTargetDatabase = $row.ArchiveTargetDatabase; CompletionMode = $CompletionMode; Status = 'Created' }
            Export-EMTReport @($journal) $config 'MoveJournal'
            $journal
        } catch {
            Write-EMTLog $config -Level ERROR -Event MOVE_EXECUTION_STOPPED
            throw 'Move execution or journaling failed. Earlier requests may exist. Inspect Exchange and the journal before retrying; no requests were removed.'
        }
    }
}
