#requires -Version 5.1
<#
.SYNOPSIS
Run migration-specific readiness checks; general server health belongs to HealthChecker.
.PARAMETER HealthCheckerReportPath
Path to reviewed HealthChecker evidence. Existence is not interpreted as a health PASS.
.PARAMETER ExitWithStatus
For a separate powershell.exe process: 0=no WARN/FAIL, 1=WARN, 2=FAIL, 3=fatal error.
.EXAMPLE
.\src\Test-ExchangeMigrationReadiness.ps1 -ConfigPath .\config\local.config.psd1 -Html
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [string]$HealthCheckerReportPath, [switch]$Html, [switch]$ExitWithStatus)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Common.psm1')
Import-Module (Join-Path $PSScriptRoot 'Common/ExchangeMigration.Checks.psm1')
try {
    $config = Read-EMTConfig $ConfigPath
    $results = @(Get-EMTReadiness $config $HealthCheckerReportPath)
    Export-EMTReport $results $config 'MigrationReadiness' -Html:$Html
    $results
    if ($ExitWithStatus) { exit (Get-EMTExitCode $results) }
} catch { if ($ExitWithStatus) { Write-Error $_ -ErrorAction Continue; exit 3 }; throw }
