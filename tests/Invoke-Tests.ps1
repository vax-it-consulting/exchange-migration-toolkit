#requires -Version 5.1
<#
.SYNOPSIS
Parse all PowerShell files, run offline smoke tests, then Pester 5.7.1 unit tests.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'smoke/Invoke-SmokeTests.ps1')
    & (Join-Path $PSScriptRoot 'smoke/Invoke-MockedWorkflow.ps1')
    Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path $PSScriptRoot 'unit'
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0 -or $result.Result -ne 'Passed') { exit 1 }
    exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
