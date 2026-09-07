#requires -Version 5.1
<#
.SYNOPSIS
Return move statistics to the pipeline and export CSV/optional HTML.
.PARAMETER IncludeFailureDetails
Include potentially sensitive Exchange failure text in protected reports. Off by default.
.EXAMPLE
.\src\Get-MoveRequestReport.ps1 -ConfigPath .\config\local.config.psd1 -BatchName Pilot-01 -Html
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [string]$BatchName, [switch]$IncludeFailureDetails, [switch]$Html)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
$config = Read-EMTConfig $ConfigPath
try {
    $argsMap = @{ ResultSize = 'Unlimited' }
    if ($BatchName) { $argsMap.BatchName = $BatchName }
    $requests = @(Invoke-EMTCommand Get-MoveRequest $argsMap)
    $rows = @(foreach ($request in $requests) {
        $stats = $null; $status = 'PASS'
        try { $stats = Invoke-EMTCommand Get-MoveRequestStatistics @{ Identity = $request.Identity } }
        catch { $status = 'WARN' }
        $failure = if ($IncludeFailureDetails) { [string](Get-EMTProperty $stats Message) } elseif (Get-EMTProperty $stats Message) { 'Omitted; use IncludeFailureDetails in a protected location.' } else { '' }
        [pscustomobject][ordered]@{
            Mailbox = [string]$request.Identity; BatchName = [string](Get-EMTProperty $request BatchName)
            Status = [string](Get-EMTProperty $stats Status (Get-EMTProperty $request Status))
            PercentComplete = Get-EMTProperty $stats PercentComplete
            SourceDatabase = [string](Get-EMTProperty $stats SourceDatabase)
            TargetDatabase = [string](Get-EMTProperty $stats TargetDatabase)
            SourceArchiveDatabase = [string](Get-EMTProperty $stats SourceArchiveDatabase)
            TargetArchiveDatabase = [string](Get-EMTProperty $stats TargetArchiveDatabase)
            TotalMailboxSize = [string](Get-EMTProperty $stats TotalMailboxSize)
            TotalArchiveSize = [string](Get-EMTProperty $stats TotalArchiveSize)
            BytesTransferred = [string](Get-EMTProperty $stats BytesTransferred)
            BytesTransferredPerMinute = [string](Get-EMTProperty $stats BytesTransferredPerMinute)
            StatusDetail = [string](Get-EMTProperty $stats StatusDetail)
            StalledReason = [string](Get-EMTProperty $stats StatusDetail)
            FailureType = [string](Get-EMTProperty $stats FailureType); FailureMessage = $failure
            BadItemsEncountered = Get-EMTProperty $stats BadItemsEncountered
            LargeItemsEncountered = Get-EMTProperty $stats LargeItemsEncountered
            QueuedTimestamp = Get-EMTProperty $stats QueuedTimestamp
            StartTimestamp = Get-EMTProperty $stats StartTimestamp
            CompletionTimestamp = Get-EMTProperty $stats CompletionTimestamp
            OverallDuration = [string](Get-EMTProperty $stats OverallDuration)
            CollectionStatus = $status
        }
    })
    Export-EMTReport $rows $config 'MoveStatus' -Html:$Html
    $rows
} catch { Write-EMTLog $config -Level ERROR -Event MOVE_REPORT_FAILED; throw }
