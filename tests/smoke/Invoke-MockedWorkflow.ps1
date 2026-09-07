#requires -Version 5.1
<#
.SYNOPSIS
Offline end-to-end workflow using synthetic cmdlets in a disposable PowerShell process.
.DESCRIPTION
Run in a fresh non-Exchange process. Refuses to shadow existing Exchange cmdlets.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$stubNames = @('Get-Mailbox','Get-MailboxStatistics','Get-MailboxDatabase','Get-MoveRequest','Get-MoveRequestStatistics','New-MoveRequest')
foreach ($name in $stubNames) { if (Get-Command $name -ErrorAction SilentlyContinue) { throw 'Use a fresh PowerShell process without Exchange cmdlets for synthetic tests.' } }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('emt-workflow-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $temp
$global:EMTSmokeMoves = [Collections.Generic.List[object]]::new()
$global:EMTSmokeExisting = $false
function global:Get-Mailbox {
    [CmdletBinding()]param($Identity,$ResultSize,$RecipientTypeDetails)
    [pscustomobject]@{Identity='pilot@example.test';ExchangeGuid='00000000-0000-0000-0000-000000000001';DisplayName='Synthetic pilot';PrimarySmtpAddress='pilot@example.test';RecipientTypeDetails='UserMailbox';Database='DB-Source-01';ArchiveDatabase='DB-Archive-Source';ArchiveGuid='00000000-0000-0000-0000-000000000002';ArchiveStatus='Active'}
}
function global:Get-MailboxStatistics {
    [CmdletBinding()]param($Identity,[switch]$Archive,$Database)
    [pscustomobject]@{TotalItemSize=$(if ($Archive) {2000L} else {100L});ItemCount=10;ServerName='ex19.example.test'}
}
function global:Get-MailboxDatabase {
    [CmdletBinding()]param($Identity,[switch]$Status)
    [pscustomobject]@{Name=$Identity;Guid=$Identity;Mounted=$true}
}
function global:Get-MoveRequest {
    [CmdletBinding()]param($ResultSize,$BatchName)
    if ($global:EMTSmokeExisting) { [pscustomobject]@{Identity='pilot@example.test';ExchangeGuid='00000000-0000-0000-0000-000000000001';Status='InProgress';BatchName='Smoke'} }
}
function global:Get-MoveRequestStatistics {
    [CmdletBinding()]param($Identity)
    [pscustomobject]@{Status='InProgress';PercentComplete=30;StatusDetail='CopyingMessages';BytesTransferred='30 B'}
}
function global:New-MoveRequest {
    [CmdletBinding()]param($Identity,$TargetDatabase,$ArchiveTargetDatabase,$BatchName,[switch]$PrimaryOnly,[switch]$ArchiveOnly,[switch]$SuspendWhenReadyToComplete,[datetime]$CompleteAfter)
    $global:EMTSmokeMoves.Add(@{} + $PSBoundParameters)
}
try {
    $configPath = Join-Path $temp 'smoke.config.psd1'
    $safeTemp = $temp.Replace("'","''")
    (Get-Content (Join-Path $repo 'config/example.config.psd1') -Raw).Replace("'output'","'$safeTemp'").Replace("'logs'","'$safeTemp'") | Set-Content $configPath -Encoding UTF8
    $inventory = @(& (Join-Path $repo 'src/Get-ExchangeInventory.ps1') -ConfigPath $configPath -Html)
    if ($inventory.Count -ne 1 -or $inventory[0].PrimaryBytes -ne 100 -or $inventory[0].ArchiveBytes -ne 2000) { throw 'Inventory mismatch.' }
    $plan = @(& (Join-Path $repo 'src/New-ExchangeMigrationPlan.ps1') -ConfigPath $configPath -Identity pilot@example.test -Html)
    if ($plan[0].EstimatedPayloadBytes -ne 100) { throw 'Plan payload mismatch.' }
    $before = @(Get-ChildItem $temp).Count
    & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath $configPath -Identity pilot@example.test -BatchName Smoke -WhatIf
    if ($global:EMTSmokeMoves.Count -ne 0 -or @(Get-ChildItem $temp).Count -ne $before) { throw 'WhatIf caused a write.' }
    & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath $configPath -Identity pilot@example.test -BatchName Smoke -Confirm:$false
    if ($global:EMTSmokeMoves.Count -ne 1 -or -not $global:EMTSmokeMoves[0].PrimaryOnly -or -not $global:EMTSmokeMoves[0].SuspendWhenReadyToComplete) { throw 'Unsafe default move parameters.' }
    $global:EMTSmokeExisting = $true
    $blocked = $false
    try { & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath $configPath -Identity pilot@example.test -BatchName Smoke -Confirm:$false } catch { $blocked = $true }
    if (-not $blocked -or $global:EMTSmokeMoves.Count -ne 1) { throw 'Existing request was not blocked.' }
    $report = @(& (Join-Path $repo 'src/Get-MoveRequestReport.ps1') -ConfigPath $configPath -BatchName Smoke -Html)
    if ($report.Count -ne 1 -or $report[0].PercentComplete -ne 30) { throw 'Move report mismatch.' }
    $csv = @((Get-ChildItem $temp -Filter '*.csv').FullName)
    $customerReport = & (Join-Path $repo 'src/New-ExchangeMigrationReport.ps1') -ConfigPath $configPath -CsvPath $csv
    if (-not (Test-Path -LiteralPath $customerReport)) { throw 'Customer report missing.' }
    Write-Output 'PASS: synthetic inventory, plan, WhatIf, safe creation, existing-request blocker, monitoring and customer report.'
} finally {
    foreach ($name in $stubNames) { Remove-Item "Function:\$name" -ErrorAction SilentlyContinue }
    Remove-Variable EMTSmokeMoves,EMTSmokeExisting -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
