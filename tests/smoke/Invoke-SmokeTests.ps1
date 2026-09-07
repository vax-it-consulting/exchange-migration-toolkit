#requires -Version 5.1
<#
.SYNOPSIS
Run offline checks without Pester or Exchange. Exit 0 on success; throws on failure.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('emt-smoke-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $temp
function Assert-Smoke { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }
try {
    Import-Module (Join-Path $repo 'src/Common/ExchangeMigration.Common.psm1') -Force
    $config = Read-EMTConfig (Join-Path $repo 'config/example.config.psd1')
    $config.OutputPath = $temp; $config.LogPath = $temp
    Assert-Smoke (@(Resolve-EMTMailboxList -Identity @('a@example.test','A@example.test')).Count -eq 1) 'Deduplication failed.'
    $row = New-EMTResult Smoke Local PASS 'Offline test'
    Export-EMTReport @($row) $config Smoke -Html
    Assert-Smoke (@(Get-ChildItem $temp -Filter '*.csv').Count -eq 1) 'Missing CSV.'
    Assert-Smoke (@(Get-ChildItem $temp -Filter '*.html').Count -eq 1) 'Missing HTML.'
    $files = @(Get-ChildItem $repo -Recurse -File | Where-Object Extension -in @('.ps1','.psm1','.psd1'))
    foreach ($file in $files) {
        $tokens = $null; $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        Assert-Smoke ($parseErrors.Count -eq 0) "Syntax error in $($file.Name): $parseErrors"
    }
    Write-Output "PASS: offline smoke tests; $($files.Count) PowerShell files parsed."
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
