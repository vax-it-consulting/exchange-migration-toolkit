#requires -Version 5.1
<#
.SYNOPSIS
Validate explicit mailbox identities against a chosen component mode and expected databases.
.DESCRIPTION
Repeats migration readiness checks. Missing completed requests are WARN, since an
operator may have already removed history. CompletedWithWarning requires review.
.EXAMPLE
.\src\Test-PostMigration.ps1 -ConfigPath .\config\local.config.psd1 -Identity pilot@example.test -Mode Primary -Html
#>
[CmdletBinding(DefaultParameterSetName='Identity')]
param([Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory,ParameterSetName='Identity')][ValidateNotNullOrEmpty()][string[]]$Identity,
    [Parameter(Mandatory,ParameterSetName='Csv')][ValidateNotNullOrEmpty()][string]$CsvPath,
    [string]$TargetDatabase, [string]$ArchiveTargetDatabase,
    [ValidateSet('Primary','Archive','Both')][string]$Mode = 'Primary',
    [string]$HealthCheckerReportPath, [switch]$Html, [switch]$ExitWithStatus)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Checks.psm1')
try {
    $config = Read-EMTConfig $ConfigPath
    if (-not $TargetDatabase) { $TargetDatabase = $config.TargetDatabase }
    if (-not $ArchiveTargetDatabase) { $ArchiveTargetDatabase = $config.ArchiveTargetDatabase }
    $ids = @(Resolve-EMTMailboxList -Identity $Identity -CsvPath $CsvPath)
    $target = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $TargetDatabase }
    $archiveTarget = $null
    if ($Mode -ne 'Primary') {
        if (-not $ArchiveTargetDatabase) { throw 'Archive target is required.' }
        $archiveTarget = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $ArchiveTargetDatabase }
    }
    $requests = @(Invoke-EMTCommand Get-MoveRequest @{ ResultSize = 'Unlimited' })
    $results = @(foreach ($id in $ids) {
        Invoke-EMTCheck 'MailboxValidation' $id -OnError FAIL -Body {
            $mailbox = Invoke-EMTCommand Get-Mailbox @{ Identity = $id }
            $guid = [string]$mailbox.ExchangeGuid
            if ($Mode -ne 'Archive') {
                $currentDb = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = [string]$mailbox.Database }
                $ok = [string]$currentDb.Guid -eq [string]$target.Guid
                New-EMTResult 'PrimaryPlacement' $guid $(if ($ok) {'PASS'} else {'FAIL'}) "Current=$($currentDb.Name); Expected=$($target.Name)." 'Verify selected identity, target and request state.'
                $stats = @(Invoke-EMTCommand Get-MailboxStatistics @{ Identity = $guid })
                New-EMTResult 'PrimaryStatistics' $guid $(if ($stats.Count -eq 1) {'PASS'} else {'FAIL'}) "Records=$($stats.Count)." 'Compare item counts and sizes against baseline; exact equality is not expected during active usage.'
            }
            if ($Mode -ne 'Primary') {
                $archiveDbName = [string](Get-EMTProperty $mailbox ArchiveDatabase)
                if (-not $archiveDbName) { New-EMTResult 'ArchivePlacement' $guid FAIL 'No local archive database.' 'Verify archive enablement and location.' }
                else {
                    $currentArchive = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $archiveDbName }
                    $ok = [string]$currentArchive.Guid -eq [string]$archiveTarget.Guid
                    New-EMTResult 'ArchivePlacement' $guid $(if ($ok) {'PASS'} else {'FAIL'}) "Current=$($currentArchive.Name); Expected=$($archiveTarget.Name)." 'Review archive move state.'
                    $stats = @(Invoke-EMTCommand Get-MailboxStatistics @{ Identity = $guid; Archive = $true })
                    New-EMTResult 'ArchiveStatistics' $guid $(if ($stats.Count -eq 1) {'PASS'} else {'FAIL'}) "Records=$($stats.Count)." 'Verify archive client access and compare inventory.'
                }
            } else { New-EMTResult 'ArchivePreservation' $guid INFO "Primary-only validation; archive currently on $(Get-EMTProperty $mailbox ArchiveDatabase)." 'Compare with pre-migration inventory to verify unchanged archive placement and continued access.' }
            $matching = @($requests | Where-Object { [string](Get-EMTProperty $_ ExchangeGuid) -eq $guid -or [string]$_.Identity -eq [string]$mailbox.Identity })
            if ($matching.Count -eq 0) { New-EMTResult 'MoveCompletion' $guid WARN 'No request history found.' 'Supply retained completion evidence; database placement alone does not prove successful completion.' }
            foreach ($request in $matching) {
                $state = [string]$request.Status
                $status = if ($state -eq 'Completed') {'PASS'} elseif ($state -eq 'CompletedWithWarning') {'WARN'} else {'FAIL'}
                New-EMTResult 'MoveCompletion' $guid $status "Status=$state." 'Review move statistics, skipped items and the retained journal.'
            }
        }
    }; Get-EMTReadiness $config $HealthCheckerReportPath)
    Export-EMTReport $results $config 'PostMigrationValidation' -Html:$Html
    $results
    if ($ExitWithStatus) { exit (Get-EMTExitCode $results) }
} catch { if ($ExitWithStatus) { Write-Error $_ -ErrorAction Continue; exit 3 }; throw }
