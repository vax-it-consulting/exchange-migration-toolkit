#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ExchangeMigration.Common.psm1')

function Invoke-EMTCheck {
    [CmdletBinding()]
    param([string]$Name, [string]$Target, [scriptblock]$Body,
        [ValidateSet('WARN','FAIL')][string]$OnError = 'WARN')
    try {
        $results = @(& $Body)
        if ($results.Count -eq 0) { New-EMTResult $Name $Target WARN 'No results returned; not verified.' 'Verify RBAC, scope and collection manually.' }
        else { $results }
    } catch { New-EMTResult $Name $Target $OnError "Not verified: $($_.Exception.GetType().Name)." 'Run the documented native cmdlet interactively; check RBAC and connectivity.' }
}

function Get-EMTReadiness {
    [CmdletBinding()]
    param([hashtable]$Config, [string]$HealthCheckerReportPath)
    if ($HealthCheckerReportPath -and (Test-Path -LiteralPath $HealthCheckerReportPath -PathType Leaf)) {
        New-EMTResult 'HealthChecker' 'Environment' INFO 'HealthChecker evidence supplied; contents and freshness require human review.' 'Attach the reviewed report, record version/hash and sign off all relevant findings.'
    } else { New-EMTResult 'HealthChecker' 'Environment' WARN 'No HealthChecker evidence supplied.' 'Run Microsoft HealthChecker on each source/target; review build, TLS, OS, .NET, CVE and health findings.' }
    $servers = @(@($Config.SourceExchangeServers) + @($Config.TargetExchangeServers) | Select-Object -Unique)
    $dbNames = @(@($Config.SourceDatabases) + @($Config.TargetDatabase) + @($Config.ArchiveTargetDatabase) | Where-Object { $_ } | Select-Object -Unique)
    foreach ($dbName in $dbNames) {
        Invoke-EMTCheck 'Database' $dbName -OnError FAIL -Body {
            $db = Invoke-EMTCommand Get-MailboxDatabase @{ Identity = $dbName; Status = $true }
            $mounted = (Get-EMTProperty $db Mounted) -eq $true
            New-EMTResult 'DatabaseMounted' $dbName $(if ($mounted) {'PASS'} else {'FAIL'}) "Mounted=$mounted; EDB=$(Get-EMTProperty $db EdbFilePath); Logs=$(Get-EMTProperty $db LogFolderPath)." 'Check database and log capacity against the selected payload plus overhead.'
            New-EMTResult 'DatabaseCapacity' $dbName INFO "Size=$(Get-EMTProperty $db DatabaseSize); EDB internal whitespace=$(Get-EMTProperty $db AvailableNewMailboxSpace)." 'EDB whitespace is not filesystem free space. Budget recoverable items, log growth, copies and backups separately.'
        }
    }
    foreach ($server in $servers) {
        Invoke-EMTCheck 'Services' $server -Body {
            $items = @(Invoke-EMTCommand Test-ServiceHealth @{ Server = $server })
            foreach ($item in $items) {
                $ok = (Get-EMTProperty $item RequiredServicesRunning) -eq $true
                New-EMTResult 'Services' $server $(if ($ok) {'PASS'} else {'FAIL'}) "Role=$(Get-EMTProperty $item Role); stopped=$(Get-EMTProperty $item ServicesNotRunning)." 'Investigate required services using HealthChecker and the Exchange service logs.'
            }
        }
        Invoke-EMTCheck 'Version' $server -Body {
            $exchange = Invoke-EMTCommand Get-ExchangeServer @{ Identity = $server }
            New-EMTResult 'Version' $server INFO "Build=$(Get-EMTProperty $exchange AdminDisplayVersion)." 'Use HealthChecker and the current Microsoft support/coexistence matrix. This toolkit does not certify build support.'
        }
        Invoke-EMTCheck 'Volumes' $server -Body {
            $volumes = @(Invoke-EMTCommand Get-CimInstance @{ ClassName = 'Win32_Volume'; ComputerName = $server; Filter = 'DriveType=3' })
            foreach ($volume in $volumes) {
                $capacity = Get-EMTProperty $volume Capacity
                $free = Get-EMTProperty $volume FreeSpace
                if ($null -eq $capacity -or [double]$capacity -le 0 -or $null -eq $free) {
                    New-EMTResult 'VolumeFreeSpace' "$server / $($volume.Name)" WARN 'Capacity unavailable.' 'Check the volume manually.'
                } else {
                    $percent = [math]::Round(100 * [double]$free / [double]$capacity, 2)
                    New-EMTResult 'VolumeFreeSpace' "$server / $($volume.Name)" $(if ($percent -lt $Config.DiskSpaceThreshold) {'FAIL'} else {'PASS'}) "FreeBytes=$free; FreePercent=$percent." 'Map EdbFilePath and LogFolderPath to these volumes, including mount points. Threshold PASS does not establish sufficient migration capacity.'
                }
            }
        }
        Invoke-EMTCheck 'Queues' $server -Body {
            $queues = @(Invoke-EMTCommand Get-Queue @{ Server = $server })
            if ($queues.Count -eq 0) { New-EMTResult 'Queues' $server INFO 'No queues returned.' 'Verify server role and transport service.' }
            foreach ($queue in $queues) {
                $bad = [string]$queue.Status -in @('Retry','Suspended') -or [long]$queue.MessageCount -ge $Config.WarningThresholds.QueueMessageCount
                New-EMTResult 'Queues' ([string]$queue.Identity) $(if ($bad) {'WARN'} else {'PASS'}) "Status=$($queue.Status); MessageCount=$($queue.MessageCount)." 'Compare queue trend and delivery errors with the baseline; do not delete queued messages.'
            }
        }
        Invoke-EMTCheck 'CertificateAvailability' $server -Body {
            $certificates = @(Invoke-EMTCommand Get-ExchangeCertificate @{ Server = $server })
            foreach ($service in @('IIS','SMTP')) {
                $bound = @($certificates | Where-Object { [string]$_.Services -match $service -and [string]$_.Status -eq 'Valid' -and (Get-EMTProperty $_ HasPrivateKey) -eq $true })
                New-EMTResult 'CertificateAvailability' "$server / $service" $(if ($bound.Count) {'PASS'} else {'FAIL'}) "$($bound.Count) valid certificate(s) with private key assigned to service." 'HealthChecker owns expiry/TLS analysis. Manually verify the certificate actually served, namespace SANs, trust chain and load balancer binding.'
            }
        }
        Invoke-EMTCheck 'ReceiveConnectors' $server -Body {
            foreach ($connector in @(Invoke-EMTCommand Get-ReceiveConnector @{ Server = $server })) {
                New-EMTResult 'ReceiveConnector' ([string]$connector.Identity) $(if ($connector.Enabled) {'INFO'} else {'WARN'}) "Enabled=$($connector.Enabled); FQDN=$($connector.Fqdn)." 'Compare bindings, permissions, relay restrictions and TLS with the inventory baseline; enabled is not a mail-flow test.'
            }
        }
        Invoke-EMTCheck 'Autodiscover' $server -Body {
            $cas = Invoke-EMTCommand Get-ClientAccessService @{ Identity = $server }
            $uri = [string](Get-EMTProperty $cas AutoDiscoverServiceInternalUri)
            $ok = $false
            if ($uri) { $ok = ([uri]$uri).DnsSafeHost -eq $Config.AutodiscoverNamespace -and ([uri]$uri).Scheme -eq 'https' }
            New-EMTResult 'AutodiscoverSCP' $server $(if ($ok) {'PASS'} else {'WARN'}) "SCP=$uri." 'Confirm split DNS, SCP design and actual client Autodiscover responses.'
        }
        foreach ($kind in @('Owa','Ecp','WebServices','Mapi','Oab','ActiveSync')) {
            Invoke-EMTCheck 'VirtualDirectory' "$server / $kind" -Body {
                foreach ($vdir in @(Invoke-EMTCommand "Get-$($kind)VirtualDirectory" @{ Server = $server })) {
                    foreach ($field in @('InternalUrl','ExternalUrl')) {
                        $value = [string](Get-EMTProperty $vdir $field)
                        $status = 'INFO'
                        if ($value) { $status = if (([uri]$value).DnsSafeHost -eq $Config.PrimaryNamespace -and ([uri]$value).Scheme -eq 'https') {'PASS'} else {'WARN'} }
                        New-EMTResult 'VirtualDirectory' "$($vdir.Identity) / $field" $status "URL=$value." 'Empty URLs can be intentional. Compare with the approved namespace design and test actual HTTPS access.'
                    }
                }
            }
        }
        foreach ($port in $Config.ReachabilityPorts) {
            Invoke-EMTCheck 'Reachability' "$server / $port" -Body {
                $test = Invoke-EMTCommand Test-NetConnection @{ ComputerName = $server; Port = $port; InformationLevel = 'Quiet'; WarningAction = 'SilentlyContinue' }
                New-EMTResult 'ReachabilityFromShellHost' "$server / $port" $(if ($test -eq $true) {'PASS'} else {'FAIL'}) 'TCP connection from the computer running this shell.' 'Separately verify Exchange-to-Exchange paths, MRS, RPC and firewalls in both directions.'
            }
        }
        if ($Config.EnableMailFlowTest) {
            Invoke-EMTCheck 'MailFlow' $server -Body {
                foreach ($flow in @(Invoke-EMTCommand Test-Mailflow @{ Identity = $server })) {
                    New-EMTResult 'MailFlow' $server $(if ([string]$flow.TestMailflowResult -eq 'Success') {'PASS'} else {'FAIL'}) "Result=$($flow.TestMailflowResult)." 'Native server test only; perform internal/external and application relay tests separately.'
                }
            }
        } else { New-EMTResult 'MailFlow' $server INFO 'Test-message generation disabled in config.' 'Run approved native Test-Mailflow and external/client tests before sign-off.' }
        Invoke-EMTCheck 'EventIndicators' $server -Body {
            # No raw event messages are persisted. Bound result size and expose truncation.
            try {
                $events = @(Invoke-EMTCommand Get-WinEvent @{ ComputerName = $server; FilterHashtable = @{ LogName = 'Application'; Level = @(2,3); ProviderName = 'MSExchange*'; StartTime = (Get-Date).AddHours(-$Config.WarningThresholds.EventLookbackHours) }; MaxEvents = $Config.WarningThresholds.EventMaxEvents })
            } catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $events = @() } else { throw }
            }
            New-EMTResult 'EventIndicators' $server $(if ($events.Count) {'WARN'} else {'PASS'}) "Exchange warning/error count=$($events.Count); cap=$($Config.WarningThresholds.EventMaxEvents); IDs=$(($events | Select-Object -ExpandProperty Id -Unique) -join ',')." 'Compare with baseline; reaching the cap means results are truncated. Use CSS-Exchange ExchangeLogCollector for incident evidence.'
        }
    }
    Invoke-EMTCheck 'DAG' 'Organization' -Body {
        $dags = @(Invoke-EMTCommand Get-DatabaseAvailabilityGroup @{ Status = $true })
        if ($dags.Count -eq 0) { New-EMTResult 'DAG' 'Organization' INFO 'No DAG exists.' }
        foreach ($dag in $dags) {
            foreach ($member in @($dag.Servers)) {
                if (@($servers | Where-Object { ($_ -split '\.')[0] -eq ([string]$member -split '\.')[0] }).Count -eq 0) { continue }
                foreach ($test in @(Invoke-EMTCommand Test-ReplicationHealth @{ Identity = [string]$member })) {
                    New-EMTResult 'DAGReplication' "$member / $($test.Check)" $(if ([string]$test.Result -eq 'Passed') {'PASS'} else {'FAIL'}) "Result=$($test.Result)." 'Investigate native Test-ReplicationHealth and database copy status before moving data.'
                }
            }
        }
    }
    foreach ($name in @($Config.PrimaryNamespace,$Config.AutodiscoverNamespace)) {
        Invoke-EMTCheck 'DNS' $name -OnError FAIL -Body {
            $records = @(Invoke-EMTCommand Resolve-DnsName @{ Name = $name; DnsOnly = $true })
            New-EMTResult 'DNSFromShellHost' $name $(if ($records.Count) {'PASS'} else {'FAIL'}) "$($records.Count) DNS records returned." 'Verify expected VIP/IP and internal/external resolution manually.'
        }
    }
    Invoke-EMTCheck 'AcceptedDomains' 'Organization' -OnError FAIL -Body {
        $domains = @(Invoke-EMTCommand Get-AcceptedDomain)
        foreach ($domain in $Config.AcceptedDomains) {
            $found = @($domains | Where-Object { [string]$_.DomainName -eq $domain }).Count -gt 0
            New-EMTResult 'AcceptedDomain' $domain $(if ($found) {'PASS'} else {'FAIL'}) "Present=$found." 'Confirm Authoritative/InternalRelay design and routing.'
        }
    }
    Invoke-EMTCheck 'SendConnectors' 'Organization' -Body {
        foreach ($connector in @(Invoke-EMTCommand Get-SendConnector)) {
            New-EMTResult 'SendConnector' ([string]$connector.Name) $(if ($connector.Enabled) {'INFO'} else {'WARN'}) "Enabled=$($connector.Enabled)." 'Compare address spaces, source servers, smart hosts and TLS against the baseline.'
        }
    }
    Invoke-EMTCheck 'ExistingMoves' 'Organization' -OnError FAIL -Body {
        $moves = @(Invoke-EMTCommand Get-MoveRequest @{ ResultSize = 'Unlimited' })
        New-EMTResult 'ExistingMoves' 'Organization' INFO "$($moves.Count) existing requests." 'Use Get-MoveRequestReport for per-mailbox details; existing requests block new requests in the planner.'
        foreach ($move in $moves) {
            $stats = Invoke-EMTCommand Get-MoveRequestStatistics @{ Identity = $move.Identity }
            $detail = [string](Get-EMTProperty $stats StatusDetail)
            if ([string]$move.Status -eq 'Failed' -or $detail -like 'Stalled*') {
                New-EMTResult 'ExistingMoveProblem' ([string]$move.Identity) $(if ([string]$move.Status -eq 'Failed') {'FAIL'} else {'WARN'}) "Status=$($move.Status); Detail=$detail." 'Investigate before increasing migration concurrency.'
            }
        }
    }
    New-EMTResult 'MailboxReadiness' 'Selected mailboxes' INFO 'Per-mailbox sizes, archives, existing requests and target placement are checked by New-ExchangeMigrationPlan.' 'Generate and review a plan for the exact selected identities; resolve every Review row.'
}
Export-ModuleMember -Function *-EMT*
