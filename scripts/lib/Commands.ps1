$script:MIN_PROFILE_SEGMENTS = 2

function Get-PathSegmentCount {
    param([string]$Normalized)
    $segments = @($Normalized.Substring($script:DRIVE_ROOT_LENGTH).Split('\') | Where-Object { $_.Length -gt 0 })
    return $segments.Count
}

# A base folder must be an existing real directory at least two levels below a drive
# root; anything shallower would turn large parts of the disk into an allowed root.
function Test-BaseDirectorySane {
    param([string]$Path)
    $normalized = Get-NormalizedPath -Path $Path
    if ($null -eq $normalized) { return $false }
    if (-not (Test-RealDirectory -Path $normalized)) { return $false }
    return ((Get-PathSegmentCount -Normalized $normalized) -ge $script:MIN_PROFILE_SEGMENTS)
}

# USERPROFILE is only an environment variable. When Windows reports the account's
# real profile and USERPROFILE points somewhere strictly inside it, a personal
# folder would be treated as the home directory, so the run is refused.
function Test-ProfileTrusted {
    $profileRoot = Get-NormalizedPath -Path $env:USERPROFILE
    $accountRoot = Get-NormalizedPath -Path (Get-AccountProfilePath)
    if (($null -eq $profileRoot) -or ($null -eq $accountRoot)) { return $true }
    return (-not (Test-PathInside -Child $profileRoot -Parent $accountRoot))
}

# APPDATA may legitimately be unset or redirected to a network share; such a value
# never becomes an allowed root. A local APPDATA must not be shallow.
function Test-EnvironmentSane {
    if (-not (Test-BaseDirectorySane -Path $env:USERPROFILE)) { return $false }
    if (-not (Test-ProfileTrusted)) { return $false }
    if (-not (Test-BaseDirectorySane -Path $env:LOCALAPPDATA)) { return $false }
    $roamingRoot = Get-NormalizedPath -Path $env:APPDATA
    if ($null -eq $roamingRoot) { return $true }
    return ((Get-PathSegmentCount -Normalized $roamingRoot) -ge $script:MIN_PROFILE_SEGMENTS)
}

function Get-RunContext {
    param([int]$MinAgeDays, [bool]$Deep, [string]$ProjectsDir, [int]$MinIdleDays, $Sink)
    $now = Get-UtcNow
    $projectsRoot = $ProjectsDir
    if ([string]::IsNullOrEmpty($projectsRoot)) { $projectsRoot = Get-NormalizedPath -Path $env:USERPROFILE }
    return [pscustomobject]@{
        NowUtc       = $now
        AgeCutoff    = $now.AddDays(-1 * $MinAgeDays)
        Deep         = $Deep
        ProjectsRoot = $projectsRoot
        MinIdleDays  = $MinIdleDays
        Sink         = $Sink
    }
}

function Get-CategoryMeasure {
    param($Category, $Context)
    try {
        $kind = $Category['Kind']
        if ($kind -eq 'directory') { return (Get-DirectoryScan -Id $Category['Id'] -Context $Context) }
        if ($kind -eq 'tool') { return (Get-ToolScan -Spec $script:TOOL_CATEGORIES[$Category['Id']]) }
        if ($kind -eq 'docker') { return (Get-DockerScan) }
        if ($kind -eq 'trash') { return (Get-TrashScan) }
        if ($kind -eq 'node-modules') { return (Get-NodeModulesScan -Context $Context) }
    } catch {
        return (Get-ScanMeasure -Status 'unavailable')
    }
    return (Get-ScanMeasure -Status 'unavailable')
}

function ConvertTo-ScanEntry {
    param($Category, $Measure)
    $entry = [ordered]@{
        id            = $Category['Id']
        label         = $Category['Label']
        group         = $Category['Group']
        size_bytes    = $Measure.Bytes
        item_count    = $Measure.Files
        status        = $Measure.Status
        recommended   = ($Category['Risk'] -eq $script:SAFE_RISK)
        risk          = $Category['Risk']
        impact        = $Category['Impact']
        requires_flag = $Category['RequiresFlag']
    }
    if ($null -ne $Measure.Buckets) { $entry['buckets'] = @($Measure.Buckets) }
    return $entry
}

function Get-RecommendedTotal {
    param([object[]]$Entries)
    $total = [long]0
    foreach ($entry in $Entries) {
        if ($entry['status'] -ne 'ok') { continue }
        if (-not $entry['recommended']) { continue }
        if ($null -eq $entry['size_bytes']) { continue }
        $total += [long]$entry['size_bytes']
    }
    return $total
}

function Invoke-ScanCommand {
    param($Options)
    $context = Get-RunContext -MinAgeDays $Options.MinAgeDays -Deep $Options.Deep `
        -ProjectsDir $Options.ProjectsDir -MinIdleDays $script:MIN_IDLE_DAYS_FLOOR -Sink $null
    $entries = @(foreach ($category in $script:CATEGORIES) {
            if ($category['DeepOnly'] -and (-not $context.Deep)) { continue }
            ConvertTo-ScanEntry -Category $category -Measure (Get-CategoryMeasure -Category $category -Context $context)
        })
    $okIds = [string[]]@($entries | Where-Object { $_['status'] -eq 'ok' } | ForEach-Object { $_['id'] })
    $token = Get-FreshToken
    Save-ScanState -Token $token -Options $Options -OkIds $okIds
    $disk = Get-DiskInfo
    return [ordered]@{
        schema_version           = $script:SCHEMA_VERSION
        command                  = $script:COMMAND_SCAN
        platform                 = $script:PLATFORM_NAME
        token                    = $token
        token_expires_in_seconds = $script:TOKEN_TTL_SECONDS
        disk                     = [ordered]@{ total_bytes = $disk.TotalBytes; free_bytes = $disk.FreeBytes }
        recommended_total_bytes  = (Get-RecommendedTotal -Entries $entries)
        categories               = $entries
    }
}

function Assert-CleanRequest {
    param($Options, $State)
    if (($Options.Categories -ccontains $script:NODE_MODULES_ID) -and (-not $State.Deep)) {
        Invoke-CleanupFailure -Code 'DEEP_SCAN_REQUIRED'
    }
    foreach ($id in $Options.Categories) {
        if ($State.Categories -cnotcontains $id) { Invoke-CleanupFailure -Code 'CATEGORY_NOT_IN_SCAN' }
    }
}

function Get-CleanOutcome {
    param($Category, $Context)
    try {
        $kind = $Category['Kind']
        if ($kind -eq 'directory') { return (Invoke-DirectoryClean -Id $Category['Id'] -Context $Context) }
        if ($kind -eq 'tool') {
            return (Invoke-ToolClean -Spec $script:TOOL_CATEGORIES[$Category['Id']] -Context $Context)
        }
        if ($kind -eq 'docker') { return (Invoke-DockerClean) }
        if ($kind -eq 'trash') { return (Invoke-TrashClean) }
        if ($kind -eq 'node-modules') { return (Invoke-NodeModulesClean -Context $Context) }
    } catch {
        return (Get-CleanState -Status 'failed' -ErrorCode 'INTERNAL')
    }
    return (Get-CleanState -Status 'failed' -ErrorCode 'INTERNAL')
}

function ConvertTo-CleanEntry {
    param($Category, $Outcome)
    return [ordered]@{
        id          = $Category['Id']
        label       = $Category['Label']
        freed_bytes = $Outcome.FreedBytes
        status      = $Outcome.Status
        error_code  = $Outcome.ErrorCode
    }
}

function Write-DeletionLog {
    param($Sink)
    try {
        $directory = [System.IO.Path]::Combine((Get-StateDirectory), $script:LOG_DIR_NAME)
        [void][System.IO.Directory]::CreateDirectory($directory)
        $name = 'clean-' + (Get-UtcNow).ToString($script:LOG_TIMESTAMP_FORMAT) + '.log'
        $lines = [string[]]@($Sink.ToArray())
        $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllLines([System.IO.Path]::Combine($directory, $name), $lines, $encoding)
    } catch {
        return $false
    }
    return $true
}

function Invoke-CleanCommand {
    param($Options)
    $state = Read-ScanState -Token $Options.Token
    Assert-CleanRequest -Options $Options -State $state
    Clear-ScanState
    $sink = $null
    if ($Options.Log) { $sink = New-Object -TypeName 'System.Collections.Generic.List[string]' }
    $context = Get-RunContext -MinAgeDays $state.MinAgeDays -Deep $state.Deep `
        -ProjectsDir $state.ProjectsDir -MinIdleDays $Options.MinIdleDays -Sink $sink
    $before = Get-DiskInfo
    $results = @(foreach ($category in $script:CATEGORIES) {
            if ($Options.Categories -cnotcontains $category['Id']) { continue }
            ConvertTo-CleanEntry -Category $category -Outcome (Get-CleanOutcome -Category $category -Context $context)
        })
    $freedTotal = [long]0
    foreach ($result in $results) { $freedTotal += [long]$result['freed_bytes'] }
    $logWritten = $false
    if ($Options.Log) { $logWritten = Write-DeletionLog -Sink $sink }
    $hint = $null
    if ($logWritten) { $hint = $script:LOG_LOCATION_HINT }
    $after = Get-DiskInfo
    return [ordered]@{
        schema_version    = $script:SCHEMA_VERSION
        command           = $script:COMMAND_CLEAN
        platform          = $script:PLATFORM_NAME
        disk_before       = [ordered]@{ free_bytes = $before.FreeBytes }
        disk_after        = [ordered]@{ free_bytes = $after.FreeBytes }
        freed_total_bytes = $freedTotal
        results           = $results
        log_file_written  = $logWritten
        log_location_hint = $hint
    }
}

function Get-CommandDocument {
    param($Options)
    if ($Options.Command -eq 'help') { return (Get-HelpDocument) }
    if ($Options.Command -eq 'version') { return (Get-VersionDocument) }
    if ($Options.Command -eq $script:COMMAND_SCAN) { return (Invoke-ScanCommand -Options $Options) }
    return (Invoke-CleanCommand -Options $Options)
}

# Runs one command line and returns the JSON document plus the process exit code.
# Never throws and never writes to the host, so tests can call it in-process.
function Invoke-Cleanup {
    param([string[]]$Arguments)
    try {
        if (-not (Test-SupportedPlatform)) { Invoke-CleanupFailure -Code 'UNSUPPORTED_PLATFORM' }
        $options = ConvertFrom-CliArgument -Arguments $Arguments
        $needsHome = ($options.Command -eq $script:COMMAND_SCAN) -or ($options.Command -eq $script:COMMAND_CLEAN)
        if ($needsHome -and (-not (Test-EnvironmentSane))) { Invoke-CleanupFailure -Code 'INTERNAL' }
        $document = Get-CommandDocument -Options $options
        $exitCode = $script:EXIT_OK
    } catch {
        $code = Get-FailureCode -Message $_.Exception.Message
        $document = Get-ErrorDocument -Code $code
        $exitCode = Get-ExitCode -Code $code
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = (ConvertTo-OutputJson -Document $document) }
}
