$script:SCHEMA_VERSION = 1
$script:TOOL_VERSION = '1.0.0'
$script:PLATFORM_NAME = 'windows'
$script:WINDOWS_OS_NAME = 'Windows_NT'
$script:JSON_DEPTH = 8

$script:EXIT_OK = 0
$script:EXIT_ERROR = 1
$script:EXIT_USAGE = 2

$script:TOKEN_TTL_SECONDS = 900
$script:TOKEN_LENGTH = 8
$script:TOKEN_PATTERN = '^[0-9a-f]{8}$'
$script:DEFAULT_MIN_AGE_DAYS = 7
$script:MIN_AGE_DAYS_FLOOR = 1
$script:DEFAULT_MIN_IDLE_DAYS = 30
$script:MIN_IDLE_DAYS_FLOOR = 30
$script:DAY_COUNT_PATTERN = '^[0-9]{1,5}$'

$script:STATE_DIR_NAME = 'disk-cleanup'
$script:STATE_FILE_NAME = 'state'
$script:LOG_DIR_NAME = 'logs'
$script:LOG_LOCATION_HINT = '%LOCALAPPDATA%\disk-cleanup\logs'
$script:LOG_TIMESTAMP_FORMAT = 'yyyyMMdd-HHmmss'
$script:EPOCH_ORIGIN = New-Object -TypeName System.DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
$script:NO_CUTOFF = [System.DateTime]::MaxValue

$script:FAILURE_PREFIX = 'disk-cleanup-failure:'
$script:ERROR_MESSAGES = @{
    'USAGE'                = 'Invalid command line. Run with --help to see the supported commands and flags.'
    'UNKNOWN_CATEGORY'     = 'A requested category id is not known on this platform. Use only ids returned by scan.'
    'TOKEN_MISSING'        = 'clean requires --token with the token printed by a recent scan.'
    'TOKEN_INVALID'        = 'The token does not match the latest scan. Run scan again.'
    'TOKEN_EXPIRED'        = 'Run scan again; the previous scan is older than 15 minutes.'
    'CATEGORY_NOT_IN_SCAN' = 'A requested category was not reported with status ok by that scan.'
    'TRASH_FLAG_REQUIRED'  = 'The trash category also requires the --empty-trash flag.'
    'DEEP_SCAN_REQUIRED'   = 'node-modules-stale requires a token from a scan run with --deep.'
    'INVALID_ARGUMENT'     = 'A flag value is not valid. Run with --help to see the accepted values.'
    'UNSUPPORTED_PLATFORM' = 'This script supports Windows only. Use cleanup.sh on macOS.'
    'INTERNAL'             = 'Unexpected internal error. Nothing further was changed.'
}

$script:USAGE_LINES = @(
    'cleanup scan [--deep] [--min-age-days N] [--projects-dir PATH]',
    'cleanup clean --token ID --categories id1,id2 [--empty-trash] [--min-idle-days N] [--log]',
    'cleanup --help',
    'cleanup --version'
)

function Invoke-CleanupFailure {
    param([string]$Code)
    throw (New-Object -TypeName System.InvalidOperationException -ArgumentList ($script:FAILURE_PREFIX + $Code))
}

function Get-FailureCode {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($Message)) { return 'INTERNAL' }
    if (-not $Message.StartsWith($script:FAILURE_PREFIX, [System.StringComparison]::Ordinal)) { return 'INTERNAL' }
    $code = $Message.Substring($script:FAILURE_PREFIX.Length)
    if ($script:ERROR_MESSAGES.ContainsKey($code)) { return $code }
    return 'INTERNAL'
}

function Get-ErrorDocument {
    param([string]$Code)
    return [ordered]@{
        schema_version = $script:SCHEMA_VERSION
        error          = [ordered]@{ code = $Code; message = $script:ERROR_MESSAGES[$Code] }
    }
}

function Get-ExitCode {
    param([string]$Code)
    if ($Code -eq 'USAGE') { return $script:EXIT_USAGE }
    return $script:EXIT_ERROR
}

function ConvertTo-OutputJson {
    param($Document)
    return (ConvertTo-Json -InputObject $Document -Depth $script:JSON_DEPTH -Compress)
}

function Get-UtcNow {
    return [System.DateTime]::UtcNow
}

function Get-EpochSecond {
    $elapsed = (Get-UtcNow) - $script:EPOCH_ORIGIN
    return [long][System.Math]::Floor($elapsed.TotalSeconds)
}

function Test-SupportedPlatform {
    return ($env:OS -eq $script:WINDOWS_OS_NAME)
}

function Get-BasePath {
    param([string]$Base)
    if ($Base -eq 'Home') { return $env:USERPROFILE }
    if ($Base -eq 'Local') { return $env:LOCALAPPDATA }
    if ($Base -eq 'Roaming') { return $env:APPDATA }
    return $null
}

function Join-BasePath {
    param([string]$Base, [string]$Relative)
    $root = Get-BasePath -Base $Base
    if ([string]::IsNullOrEmpty($root)) { return $null }
    return [System.IO.Path]::Combine($root, $Relative)
}

function Get-HelpDocument {
    return [ordered]@{
        schema_version = $script:SCHEMA_VERSION
        command        = 'help'
        platform       = $script:PLATFORM_NAME
        usage          = @($script:USAGE_LINES)
    }
}

function Get-VersionDocument {
    return [ordered]@{
        schema_version = $script:SCHEMA_VERSION
        command        = 'version'
        platform       = $script:PLATFORM_NAME
        version        = $script:TOOL_VERSION
    }
}
