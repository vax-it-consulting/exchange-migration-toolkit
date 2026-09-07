@{
    SourceExchangeServers = @('ex19.example.test')
    TargetExchangeServers = @('exse.example.test')
    SourceDatabases = @('DB-Source-01')
    TargetDatabase = 'DB-Target-01'
    ArchiveTargetDatabase = 'DB-Archive-01'
    PrimaryNamespace = 'mail.example.test'
    AutodiscoverNamespace = 'autodiscover.example.test'
    AcceptedDomains = @('example.test')
    # Relative paths are resolved from the repository root, not the current directory.
    OutputPath = 'output'
    LogPath = 'logs'
    DiskSpaceThreshold = 20 # Percent free; includes mounted volumes via Win32_Volume.
    CertificateExpiryWarningDays = 30
    WarningThresholds = @{
        QueueMessageCount = 100
        EventLookbackHours = 24
        EventMaxEvents = 200
    }
    # TCP reachability is tested FROM the shell host, not between Exchange servers.
    ReachabilityPorts = @(25, 443)
    # Keep false until test-message generation is approved for the change window.
    EnableMailFlowTest = $false
}
