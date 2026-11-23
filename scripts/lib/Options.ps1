$script:COMMAND_SCAN = 'scan'
$script:COMMAND_CLEAN = 'clean'
$script:HELP_FLAGS = @('--help', '-h')
$script:VERSION_FLAG = '--version'
$script:FLAG_PREFIX = '--'
$script:HOME_SHORTCUT = '~'

# Value $true means the flag takes a value; $false means it is a switch.
$script:FLAG_SPECS = @{
    'scan'         = @{ '--deep' = $false; '--min-age-days' = $true; '--projects-dir' = $true; '--target-gb' = $true }
    'clean'        = @{ '--token' = $true; '--categories' = $true; '--empty-trash' = $false
        '--min-idle-days' = $true; '--log' = $false }
    'review'       = @{ '--min-size-mb' = $true; '--downloads-age-days' = $true }
    'review-apply' = @{ '--token' = $true }
}
$script:NO_TARGET = 0
$script:TARGET_GB_FLOOR = 1
$script:TARGET_GB_CEILING = 10000
$script:TARGET_GB_PATTERN = '^[0-9]{1,5}$'

function Read-FlagValue {
    param([string]$Command, [string[]]$Rest)
    $spec = $script:FLAG_SPECS[$Command]
    $values = @{}
    $index = 0
    while ($index -lt $Rest.Count) {
        $name = $Rest[$index]
        $inline = $null
        $separator = $name.IndexOf('=')
        if ($name.StartsWith($script:FLAG_PREFIX) -and ($separator -gt 0)) {
            $inline = $name.Substring($separator + 1)
            $name = $name.Substring(0, $separator)
        }
        if ((-not $spec.ContainsKey($name)) -or $values.ContainsKey($name)) { Invoke-CleanupFailure -Code 'USAGE' }
        $index += 1
        if (-not $spec[$name]) {
            if ($null -ne $inline) { Invoke-CleanupFailure -Code 'USAGE' }
            $values[$name] = $true
            continue
        }
        if ($null -ne $inline) {
            $values[$name] = $inline
            continue
        }
        if ($index -ge $Rest.Count) { Invoke-CleanupFailure -Code 'USAGE' }
        if ($Rest[$index].StartsWith($script:FLAG_PREFIX)) { Invoke-CleanupFailure -Code 'USAGE' }
        $values[$name] = $Rest[$index]
        $index += 1
    }
    return $values
}

function ConvertTo-DayCount {
    param([string]$Text, [int]$Minimum)
    if ($Text -notmatch $script:DAY_COUNT_PATTERN) { Invoke-CleanupFailure -Code 'INVALID_ARGUMENT' }
    $value = [int]$Text
    if ($value -lt $Minimum) { Invoke-CleanupFailure -Code 'INVALID_ARGUMENT' }
    return $value
}

function ConvertTo-BoundedNumber {
    param([string]$Text, [string]$Pattern, [int]$Minimum, [int]$Maximum)
    if ($Text -notmatch $Pattern) { Invoke-CleanupFailure -Code 'INVALID_ARGUMENT' }
    $value = [int]$Text
    if (($value -lt $Minimum) -or ($value -gt $Maximum)) { Invoke-CleanupFailure -Code 'INVALID_ARGUMENT' }
    return $value
}

function Expand-HomeShortcut {
    param([string]$Path)
    if ($Path -eq $script:HOME_SHORTCUT) { return $env:USERPROFILE }
    if ($Path.StartsWith('~\') -or $Path.StartsWith('~/')) {
        return [System.IO.Path]::Combine($env:USERPROFILE, $Path.Substring(2))
    }
    return $Path
}

# Returns the normalized walk root for --deep, or $null when the path is not an
# existing real directory inside the user profile that the walk is allowed to enter.
function Resolve-ProjectRoot {
    param([string]$Path)
    $normalized = Get-NormalizedPath -Path (Expand-HomeShortcut -Path $Path)
    $profileRoot = Get-NormalizedPath -Path $env:USERPROFILE
    if (($null -eq $normalized) -or ($null -eq $profileRoot)) { return $null }
    if (-not [System.IO.Directory]::Exists($normalized)) { return $null }
    if ($normalized.Equals($profileRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $normalized }
    if (-not (Test-PathInside -Child $normalized -Parent $profileRoot)) { return $null }
    if (-not (Test-LinkFreeBelow -Target $normalized -Root $profileRoot)) { return $null }
    $relative = $normalized.Substring($profileRoot.Length).Trim('\')
    foreach ($segment in $relative.Split('\')) {
        if (Test-PrunedDirectoryName -Name $segment) { return $null }
    }
    return $normalized
}

function ConvertTo-ScanOption {
    param($Raw)
    $minAgeDays = $script:DEFAULT_MIN_AGE_DAYS
    if ($Raw.ContainsKey('--min-age-days')) {
        $minAgeDays = ConvertTo-DayCount -Text $Raw['--min-age-days'] -Minimum $script:MIN_AGE_DAYS_FLOOR
    }
    $projectsDir = ''
    if ($Raw.ContainsKey('--projects-dir')) {
        $projectsDir = Resolve-ProjectRoot -Path $Raw['--projects-dir']
        if ($null -eq $projectsDir) { Invoke-CleanupFailure -Code 'INVALID_ARGUMENT' }
    }
    $targetGb = $script:NO_TARGET
    if ($Raw.ContainsKey('--target-gb')) {
        $targetGb = ConvertTo-BoundedNumber -Text $Raw['--target-gb'] -Pattern $script:TARGET_GB_PATTERN `
            -Minimum $script:TARGET_GB_FLOOR -Maximum $script:TARGET_GB_CEILING
    }
    return [pscustomobject]@{
        Command     = $script:COMMAND_SCAN
        Deep        = $Raw.ContainsKey('--deep')
        MinAgeDays  = $minAgeDays
        ProjectsDir = $projectsDir
        TargetGb    = $targetGb
    }
}

function Get-KnownCategoryIdList {
    foreach ($category in $script:CATEGORIES) { $category['Id'] }
}

function ConvertTo-CategoryIdList {
    param([string]$Text)
    $known = @(Get-KnownCategoryIdList)
    $ids = @($Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 } |
            Select-Object -Unique)
    if ($ids.Count -eq 0) { Invoke-CleanupFailure -Code 'USAGE' }
    foreach ($id in $ids) {
        if ($known -cnotcontains $id) { Invoke-CleanupFailure -Code 'UNKNOWN_CATEGORY' }
    }
    return $ids
}

function ConvertTo-CleanOption {
    param($Raw)
    if (-not $Raw.ContainsKey('--categories')) { Invoke-CleanupFailure -Code 'USAGE' }
    $ids = @(ConvertTo-CategoryIdList -Text $Raw['--categories'])
    if (-not $Raw.ContainsKey('--token')) { Invoke-CleanupFailure -Code 'TOKEN_MISSING' }
    $minIdleDays = $script:DEFAULT_MIN_IDLE_DAYS
    if ($Raw.ContainsKey('--min-idle-days')) {
        $minIdleDays = ConvertTo-DayCount -Text $Raw['--min-idle-days'] -Minimum $script:MIN_IDLE_DAYS_FLOOR
    }
    $emptyTrash = $Raw.ContainsKey($script:TRASH_FLAG)
    if (($ids -ccontains $script:TRASH_ID) -and (-not $emptyTrash)) { Invoke-CleanupFailure -Code 'TRASH_FLAG_REQUIRED' }
    if ($Raw['--token'] -cnotmatch $script:TOKEN_PATTERN) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    return [pscustomobject]@{
        Command     = $script:COMMAND_CLEAN
        Token       = [string]$Raw['--token']
        Categories  = $ids
        EmptyTrash  = $emptyTrash
        MinIdleDays = $minIdleDays
        Log         = $Raw.ContainsKey('--log')
    }
}

function ConvertTo-ReviewOption {
    param($Raw)
    $minSizeMb = $script:REVIEW_DEFAULT_MIN_SIZE_MB
    if ($Raw.ContainsKey('--min-size-mb')) {
        $minSizeMb = ConvertTo-BoundedNumber -Text $Raw['--min-size-mb'] -Pattern $script:REVIEW_SIZE_MB_PATTERN `
            -Minimum $script:REVIEW_MIN_SIZE_MB_FLOOR -Maximum ([int]::MaxValue)
    }
    $downloadsAgeDays = $script:REVIEW_DEFAULT_DOWNLOADS_AGE_DAYS
    if ($Raw.ContainsKey('--downloads-age-days')) {
        $downloadsAgeDays = ConvertTo-DayCount -Text $Raw['--downloads-age-days'] `
            -Minimum $script:REVIEW_DOWNLOADS_AGE_DAYS_FLOOR
    }
    return [pscustomobject]@{
        Command          = $script:COMMAND_REVIEW
        MinSizeMb        = $minSizeMb
        DownloadsAgeDays = $downloadsAgeDays
    }
}

function ConvertTo-ReviewApplyOption {
    param($Raw)
    if (-not $Raw.ContainsKey('--token')) { Invoke-CleanupFailure -Code 'TOKEN_MISSING' }
    if ($Raw['--token'] -cnotmatch $script:TOKEN_PATTERN) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    return [pscustomobject]@{
        Command = $script:COMMAND_REVIEW_APPLY
        Token   = [string]$Raw['--token']
    }
}

function ConvertFrom-CliArgument {
    param([string[]]$Arguments)
    if (($null -eq $Arguments) -or ($Arguments.Count -eq 0)) { Invoke-CleanupFailure -Code 'USAGE' }
    $first = $Arguments[0]
    if ($script:HELP_FLAGS -ccontains $first) { return [pscustomobject]@{ Command = 'help' } }
    if ($first -ceq $script:VERSION_FLAG) { return [pscustomobject]@{ Command = 'version' } }
    $rest = [string[]]@($Arguments | Select-Object -Skip 1)
    if ($first -ceq $script:COMMAND_SCAN) {
        return (ConvertTo-ScanOption -Raw (Read-FlagValue -Command $first -Rest $rest))
    }
    if ($first -ceq $script:COMMAND_CLEAN) {
        return (ConvertTo-CleanOption -Raw (Read-FlagValue -Command $first -Rest $rest))
    }
    if ($first -ceq $script:COMMAND_REVIEW) {
        return (ConvertTo-ReviewOption -Raw (Read-FlagValue -Command $first -Rest $rest))
    }
    if ($first -ceq $script:COMMAND_REVIEW_APPLY) {
        return (ConvertTo-ReviewApplyOption -Raw (Read-FlagValue -Command $first -Rest $rest))
    }
    Invoke-CleanupFailure -Code 'USAGE'
}

function Get-StateDirectory {
    return (Join-BasePath -Base 'Local' -Relative $script:STATE_DIR_NAME)
}

function Get-StateFilePath {
    $directory = Get-StateDirectory
    if ([string]::IsNullOrEmpty($directory)) { return $null }
    return [System.IO.Path]::Combine($directory, $script:STATE_FILE_NAME)
}

function Get-FreshToken {
    return [System.Guid]::NewGuid().ToString('N').Substring(0, $script:TOKEN_LENGTH)
}

function Save-ScanState {
    param([string]$Token, $Options, [string[]]$OkIds)
    $path = Get-StateFilePath
    if ($null -eq $path) { Invoke-CleanupFailure -Code 'INTERNAL' }
    if (Test-PathIsLinkIfPresent -Path $path) { Invoke-CleanupFailure -Code 'INTERNAL' }
    $state = [ordered]@{
        token        = $Token
        epoch        = Get-EpochSecond
        min_age_days = $Options.MinAgeDays
        deep         = $Options.Deep
        projects_dir = $Options.ProjectsDir
        categories   = @($OkIds)
    }
    [void][System.IO.Directory]::CreateDirectory((Get-StateDirectory))
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($path, (ConvertTo-OutputJson -Document $state), $encoding)
}

function Test-PathIsLinkIfPresent {
    param([string]$Path)
    if (-not ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path))) { return $false }
    return (Test-PathIsLink -Path $Path)
}

# Converts the parsed state file into a typed record. Throws on any missing or
# malformed field; the caller maps that to TOKEN_INVALID.
function ConvertTo-StateRecord {
    param($State)
    $projectsDir = ''
    if (-not [string]::IsNullOrEmpty([string]$State.projects_dir)) {
        $projectsDir = Resolve-ProjectRoot -Path ([string]$State.projects_dir)
        if ($null -eq $projectsDir) { throw 'stored projects directory is no longer valid' }
    }
    if (([string]$State.token) -cnotmatch $script:TOKEN_PATTERN) { throw 'stored token is malformed' }
    return [pscustomobject]@{
        Token       = [string]$State.token
        Epoch       = [long]$State.epoch
        MinAgeDays  = [System.Math]::Max($script:MIN_AGE_DAYS_FLOOR, [int]$State.min_age_days)
        Deep        = ($State.deep -eq $true)
        ProjectsDir = $projectsDir
        Categories  = @($State.categories | ForEach-Object { [string]$_ })
    }
}

function Read-ScanState {
    param([string]$Token)
    $path = Get-StateFilePath
    $record = $null
    if (($null -ne $path) -and [System.IO.File]::Exists($path) -and (-not (Test-PathIsLink -Path $path))) {
        try {
            $parsed = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($path))
            $record = ConvertTo-StateRecord -State $parsed
        } catch {
            $record = $null
        }
    }
    if ($null -eq $record) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    if ($record.Token -cne $Token) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    $age = (Get-EpochSecond) - $record.Epoch
    if ($age -lt 0) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    if ($age -ge $script:TOKEN_TTL_SECONDS) { Invoke-CleanupFailure -Code 'TOKEN_EXPIRED' }
    return $record
}

# Burns the single-use token. Goes through the guarded delete like every other removal.
function Clear-ScanState {
    $target = Get-CleanTarget -Path (Get-StateFilePath) -KeepRoot $false
    $outcome = Invoke-GuardedDelete -Target $target -Sink $null
    if ($outcome.DeletedFiles -ne 1) { Invoke-CleanupFailure -Code 'INTERNAL' }
}
