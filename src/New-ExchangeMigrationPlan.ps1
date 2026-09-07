#requires -Version 5.1
<#
.SYNOPSIS
Create a read-only plan for explicitly selected mailbox identities.
.PARAMETER Mode
Primary (default), Archive or Both. Both requires every selected mailbox to have a local archive.
.PARAMETER CsvPath
UTF-8 comma-separated CSV with one Identity column. No target/action overrides are read.
.EXAMPLE
.\src\New-ExchangeMigrationPlan.ps1 -ConfigPath .\config\local.config.psd1 -CsvPath .\private\pilot.csv -Mode Primary -Html
#>
[CmdletBinding(DefaultParameterSetName = 'Identity')]
param([Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory,ParameterSetName='Identity')][ValidateNotNullOrEmpty()][string[]]$Identity,
    [Parameter(Mandatory,ParameterSetName='Csv')][ValidateNotNullOrEmpty()][string]$CsvPath,
    [string]$TargetDatabase, [string]$ArchiveTargetDatabase,
    [ValidateSet('Primary','Archive','Both')][string]$Mode = 'Primary', [switch]$Html)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Data.psm1')
$config = Read-EMTConfig $ConfigPath
if (-not $TargetDatabase) { $TargetDatabase = $config.TargetDatabase }
if (-not $ArchiveTargetDatabase) { $ArchiveTargetDatabase = $config.ArchiveTargetDatabase }
$ids = @(Resolve-EMTMailboxList -Identity $Identity -CsvPath $CsvPath)
try {
    $plan = @(Get-EMTPlan $ids $TargetDatabase $ArchiveTargetDatabase $Mode)
    Export-EMTReport $plan $config 'MigrationPlan' -Html:$Html
    $known = @($plan | Where-Object { $null -ne $_.EstimatedPayloadBytes })
    $payload = ($known | Measure-Object EstimatedPayloadBytes -Sum).Sum
    Write-Information ("Plan: {0} mailboxes; known selected payload: {1} bytes; Review: {2}. Excludes overhead and recoverable items." -f $plan.Count,$payload,@($plan | Where-Object MigrationAction -eq 'Review').Count) -InformationAction Continue
    $plan
} catch { Write-EMTLog $config -Level ERROR -Event PLAN_FAILED; throw }
