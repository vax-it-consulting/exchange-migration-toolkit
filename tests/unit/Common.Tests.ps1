#requires -Version 5.1
BeforeAll {
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'src/Common/ExchangeMigration.Common.psm1') -Force
    Import-Module (Join-Path $repo 'src/Common/ExchangeMigration.Data.psm1') -Force
    Import-Module (Join-Path $repo 'src/Common/ExchangeMigration.Checks.psm1') -Force
}
Describe 'Config and mailbox selection' {
    It 'imports example config and resolves output paths' {
        $c = Read-EMTConfig (Join-Path $repo 'config/example.config.psd1')
        [IO.Path]::IsPathRooted($c.OutputPath) | Should -BeTrue
        $c.EnableMailFlowTest | Should -BeFalse
    }
    It 'rejects incomplete config' {
        $path = Join-Path $TestDrive 'invalid.psd1'
        Set-Content $path '@{ TargetDatabase = "DB" }'
        { Read-EMTConfig $path } | Should -Throw
    }
    It 'rejects invalid threshold type' {
        $path = Join-Path $TestDrive 'invalid.psd1'
        (Get-Content (Join-Path $repo 'config/example.config.psd1') -Raw).Replace('DiskSpaceThreshold = 20','DiskSpaceThreshold = "twenty"') | Set-Content $path
        { Read-EMTConfig $path } | Should -Throw
    }
    It 'deduplicates trimmed identities case-insensitively' {
        $ids = @(Resolve-EMTMailboxList -Identity @(' a@example.test ','A@example.test','b@example.test'))
        $ids.Count | Should -Be 2
        $ids[0] | Should -Be 'a@example.test'
    }
    It 'rejects empty identities and wildcards' {
        { Resolve-EMTMailboxList -Identity @('') } | Should -Throw
        { Resolve-EMTMailboxList -Identity @('*') } | Should -Throw
        { Resolve-EMTMailboxList -Identity @('valid@example.test',' ') } | Should -Throw
    }
    It 'imports an Identity CSV' {
        $path = Join-Path $TestDrive 'mailboxes.csv'
        Set-Content $path "Identity`na@example.test`nb@example.test"
        @(Resolve-EMTMailboxList -CsvPath $path).Count | Should -Be 2
    }
    It 'rejects incorrect CSV headers and ambiguous sources' {
        $path = Join-Path $TestDrive 'wrong.csv'
        Set-Content $path "Mailbox`na@example.test"
        { Resolve-EMTMailboxList -CsvPath $path } | Should -Throw
        { Resolve-EMTMailboxList -CsvPath $path -Identity 'a@example.test' } | Should -Throw
    }
}
Describe 'Results and exports' {
    It 'assigns severity and aggregates status deterministically' {
        $pass = New-EMTResult Check Target PASS 'ok'
        $warn = New-EMTResult Check Target WARN 'review'
        $fail = New-EMTResult Check Target FAIL 'stop'
        $fail.Severity | Should -Be 'High'
        Get-EMTExitCode @($pass) | Should -Be 0
        Get-EMTExitCode @($pass,$warn) | Should -Be 1
        Get-EMTExitCode @($pass,$fail,$warn) | Should -Be 2
    }
    It 'escapes HTML and neutralizes spreadsheet formulas' {
        $config = @{ OutputPath = $TestDrive; LogPath = $TestDrive }
        Export-EMTReport @([pscustomobject]@{Name='<script>alert(1)</script>';Value='=1+1'}) $config 'Safe' -Html
        $csv = Import-Csv (Get-ChildItem $TestDrive -Filter 'Safe-*.csv' | Select-Object -First 1).FullName
        $csv.Value | Should -Be "'=1+1"
        $html = Get-Content (Get-ChildItem $TestDrive -Filter 'Safe-*.html' | Select-Object -First 1).FullName -Raw
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Not -Match '<script>'
    }
    It 'handles empty reports' {
        { Export-EMTReport @() @{OutputPath=$TestDrive;LogPath=$TestDrive} 'Empty' -Html } | Should -Not -Throw
    }
    It 'does not invent byte counts from rounded values' {
        ConvertTo-EMTBytes '1 GB (1,073,741,824 bytes)' | Should -Be 1073741824
        ConvertTo-EMTBytes '1 GB' | Should -BeNullOrEmpty
        ConvertTo-EMTBytes $null | Should -BeNullOrEmpty
    }
    It 'marks an unavailable check as WARN, never PASS' {
        (Invoke-EMTCheck Test Target { throw 'Unavailable' }).Status | Should -Be 'WARN'
        (Invoke-EMTCheck Test Target { } -OnError FAIL).Status | Should -Be 'WARN'
        (Invoke-EMTCheck Test Target { throw 'Unavailable' } -OnError FAIL).Status | Should -Be 'FAIL'
    }
}
Describe 'Mailbox inventory and planning with mocked Exchange' {
    InModuleScope ExchangeMigration.Data {
        BeforeEach {
            Mock Invoke-EMTCommand {
                param($Command,$Parameters)
                switch ($Command) {
                    Get-MoveRequest { return }
                    Get-MailboxDatabase {
                        $name = $Parameters.Identity
                        [pscustomobject]@{Name=$name;Guid=$name;Mounted=$true}
                    }
                    Get-Mailbox {
                        [pscustomobject]@{Identity='a@example.test';ExchangeGuid='00000000-0000-0000-0000-000000000001';DisplayName='Example';PrimarySmtpAddress='a@example.test';RecipientTypeDetails='UserMailbox';Database='Source';ArchiveDatabase='ArchiveSource';ArchiveGuid='00000000-0000-0000-0000-000000000002';ArchiveStatus='Active'}
                    }
                    Get-MailboxStatistics {
                        $size = if ($Parameters.ContainsKey('Archive')) {2000L} else {100L}
                        [pscustomobject]@{TotalItemSize=$size;ItemCount=5;ServerName='ex.example.test'}
                    }
                    default { throw "Unexpected command: $Command" }
                }
            }
        }
        It 'keeps primary and archive sizes separate' {
            $m = Invoke-EMTCommand Get-Mailbox @{}
            $row = Get-EMTMailboxRow $m Target ArchiveTarget
            $row.PrimaryBytes | Should -Be 100
            $row.ArchiveBytes | Should -Be 2000
            $row.TotalBytes | Should -Be 2100
            $row.ArchiveEnabled | Should -BeTrue
        }
        It 'plans primary payload only by default' {
            $plan = @(Get-EMTPlan @('a@example.test') Target ArchiveTarget)
            $plan[0].MigrationAction | Should -Be 'Move Primary'
            $plan[0].EstimatedPayloadBytes | Should -Be 100
        }
        It 'plans archive and both modes explicitly' {
            (Get-EMTPlan @('a@example.test') Target ArchiveTarget Archive).EstimatedPayloadBytes | Should -Be 2000
            (Get-EMTPlan @('a@example.test') Target ArchiveTarget Both).EstimatedPayloadBytes | Should -Be 2100
        }
        It 'deduplicates aliases resolving to the same ExchangeGuid' {
            @(Get-EMTPlan @('a@example.test','alias@example.test') Target ArchiveTarget).Count | Should -Be 1
        }
        It 'marks an existing request as Review' {
            Mock Invoke-EMTCommand { [pscustomobject]@{ExchangeGuid='00000000-0000-0000-0000-000000000001'} } -ParameterFilter { $Command -eq 'Get-MoveRequest' }
            (Get-EMTPlan @('a@example.test') Target ArchiveTarget).MigrationAction | Should -Be 'Review'
        }
        It 'fails closed when the existing-request query fails' {
            Mock Invoke-EMTCommand { throw 'Access denied' } -ParameterFilter { $Command -eq 'Get-MoveRequest' }
            { Get-EMTPlan @('a@example.test') Target ArchiveTarget } | Should -Throw
        }
        It 'rejects an unmounted target before planning' {
            Mock Invoke-EMTCommand { [pscustomobject]@{Name='Target';Guid='Target';Mounted=$false} } -ParameterFilter { $Command -eq 'Get-MailboxDatabase' }
            { Get-EMTPlan @('a@example.test') Target ArchiveTarget } | Should -Throw
        }
        It 'does not move primary data already on target' {
            (Get-EMTPlan @('a@example.test') Source ArchiveTarget).MigrationAction | Should -Be 'No Migration'
        }
        It 'requires archive review when statistics cannot be read' {
            Mock Invoke-EMTCommand { throw 'Unavailable' } -ParameterFilter { $Command -eq 'Get-MailboxStatistics' -and $Parameters.ContainsKey('Archive') }
            (Get-EMTPlan @('a@example.test') Target ArchiveTarget Archive).MigrationAction | Should -Be 'Review'
            (Get-EMTPlan @('a@example.test') Target ArchiveTarget Primary).MigrationAction | Should -Be 'Move Primary'
        }
    }
}

Describe 'Readiness with mocked Windows and Exchange boundaries' {
    InModuleScope ExchangeMigration.Checks {
        BeforeEach {
            $config = @{
                SourceExchangeServers=@('ex19.example.test');TargetExchangeServers=@('exse.example.test')
                SourceDatabases=@('Source');TargetDatabase='Target';ArchiveTargetDatabase='Archive'
                PrimaryNamespace='mail.example.test';AutodiscoverNamespace='autodiscover.example.test'
                AcceptedDomains=@('example.test');DiskSpaceThreshold=20;EnableMailFlowTest=$false
                ReachabilityPorts=@(443);WarningThresholds=@{QueueMessageCount=100;EventLookbackHours=24;EventMaxEvents=200}
            }
            Mock Invoke-EMTCommand {
                param($Command,$Parameters)
                switch ($Command) {
                    Get-MailboxDatabase { [pscustomobject]@{Mounted=$true} }
                    Get-ExchangeServer { [pscustomobject]@{AdminDisplayVersion='Synthetic build'} }
                    Get-AcceptedDomain { [pscustomobject]@{DomainName='example.test'} }
                    Get-CimInstance { [pscustomobject]@{Name='D:\';Capacity=1000L;FreeSpace=500L} }
                    Resolve-DnsName { [pscustomobject]@{Name='mail.example.test'} }
                    Test-NetConnection { $true }
                    default { return }
                }
            }
        }
        It 'reports missing health evidence as WARN while preserving successful native checks' {
            $results = @(Get-EMTReadiness $config)
            ($results | Where-Object Check -eq 'HealthChecker').Status | Should -Be 'WARN'
            @($results | Where-Object { $_.Check -eq 'DatabaseMounted' -and $_.Status -eq 'PASS' }).Count | Should -Be 3
        }
        It 'reports low free space as FAIL' {
            Mock Invoke-EMTCommand { [pscustomobject]@{Name='D:\';Capacity=1000L;FreeSpace=50L} } -ParameterFilter { $Command -eq 'Get-CimInstance' }
            $results = @(Get-EMTReadiness $config)
            @($results | Where-Object { $_.Check -eq 'VolumeFreeSpace' -and $_.Status -eq 'FAIL' }).Count | Should -Be 2
        }
        It 'does not call Test-Mailflow when disabled' {
            $null = @(Get-EMTReadiness $config)
            Should -Invoke Invoke-EMTCommand -Times 0 -Exactly -ParameterFilter { $Command -eq 'Test-Mailflow' }
        }
        It 'fails a required database read rather than assuming success' {
            Mock Invoke-EMTCommand { throw 'Access denied' } -ParameterFilter { $Command -eq 'Get-MailboxDatabase' }
            $results = @(Get-EMTReadiness $config)
            @($results | Where-Object { $_.Check -eq 'Database' -and $_.Status -eq 'FAIL' }).Count | Should -Be 3
        }
    }
}

Describe 'Start parameter validation before Exchange access' {
    It 'rejects conflicting primary/archive switches' {
        { & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath (Join-Path $repo 'config/example.config.psd1') -Identity 'a@example.test' -BatchName Pilot -PrimaryOnly -ArchiveOnly -WhatIf } | Should -Throw
    }
    It 'rejects scheduled mode without a future completion time' {
        { & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath (Join-Path $repo 'config/example.config.psd1') -Identity 'a@example.test' -BatchName Pilot -CompletionMode Scheduled -WhatIf } | Should -Throw
    }
    It 'rejects a completion time outside scheduled mode' {
        { & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath (Join-Path $repo 'config/example.config.psd1') -Identity 'a@example.test' -BatchName Pilot -CompleteAfter (Get-Date).AddHours(1) -WhatIf } | Should -Throw
    }
    It 'rejects batch names containing spaces' {
        { & (Join-Path $repo 'src/Start-MailboxMigration.ps1') -ConfigPath (Join-Path $repo 'config/example.config.psd1') -Identity 'a@example.test' -BatchName 'Invalid batch' -WhatIf } | Should -Throw
    }
}
