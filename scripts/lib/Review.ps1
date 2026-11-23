$script:COMMAND_REVIEW = 'review'
$script:COMMAND_REVIEW_APPLY = 'review-apply'
$script:REVIEW_TOKEN_TTL_SECONDS = 3600
$script:REVIEW_DEFAULT_MIN_SIZE_MB = 100
$script:REVIEW_MIN_SIZE_MB_FLOOR = 10
$script:REVIEW_SIZE_MB_PATTERN = '^[0-9]{1,7}$'
$script:REVIEW_DEFAULT_DOWNLOADS_AGE_DAYS = 90
$script:REVIEW_DOWNLOADS_AGE_DAYS_FLOOR = 7
$script:BYTES_PER_MEGABYTE = [long]1048576
$script:REVIEW_MAX_ITEMS = 500
$script:REVIEW_MANIFEST_NAME = 'review-manifest'
$script:REVIEW_REPORT_NAME = 'review.html'
$script:REVIEW_REPORT_HINT = '%LOCALAPPDATA%\disk-cleanup\review.html'
$script:REVIEW_SELECTION_HINT = 'Downloads/disk-cleanup-selection.json'
$script:DOWNLOADS_DIR_NAME = 'Downloads'
$script:REVIEW_GROUP_LARGE = 'large-files'
$script:REVIEW_GROUP_DOWNLOADS = 'old-downloads'
$script:REVIEW_GROUPS = @(
    @{ Id = 'large-files'; Label = 'Large files' },
    @{ Id = 'old-downloads'; Label = 'Old items in Downloads' }
)

# Folders that are one opaque thing to their owner (app bundles, photo and video
# libraries, virtual machines). They are never entered, on either platform.
$script:REVIEW_BUNDLE_SUFFIXES = @(
    '.app', '.photoslibrary', '.musiclibrary', '.tvlibrary', '.imovielibrary', '.fcpbundle', '.logicx', '.band',
    '.sparsebundle', '.vmwarevm', '.pvm', '.utm', '.bundle', '.framework', '.xcodeproj', '.lrcat', '.lrdata'
)
$script:REVIEW_PRUNED_DIR_NAMES = @('$RECYCLE.BIN')

# Longer paths cannot be handed to the Recycle Bin by Windows PowerShell 5.1.
$script:MAX_PATH_LENGTH = 260
$script:DIRECTORY_FLAG = [int][System.IO.FileAttributes]::Directory
$script:REVIEW_HIDDEN_FLAGS = ([int][System.IO.FileAttributes]::Hidden) -bor ([int][System.IO.FileAttributes]::System)

# Offline, RecallOnOpen (0x40000) and RecallOnDataAccess (0x400000) mark files whose
# content lives in the cloud. Recycling one would remove the cloud copy and free nothing.
$script:OFFLINE_FLAG = [int][System.IO.FileAttributes]::Offline
$script:RECALL_ON_OPEN_FLAG = 262144
$script:RECALL_ON_DATA_ACCESS_FLAG = 4194304
$script:CLOUD_PLACEHOLDER_FLAGS = $script:OFFLINE_FLAG -bor $script:RECALL_ON_OPEN_FLAG -bor $script:RECALL_ON_DATA_ACCESS_FLAG

# Line and paragraph separators plus the characters that reorder displayed text.
$script:REVIEW_UNSAFE_CHAR_CODES = @(8232, 8233, 8234, 8235, 8236, 8237, 8238, 8294, 8295, 8296, 8297)

$script:MANIFEST_HEADER = 'disk-cleanup-review-manifest 1'
$script:MANIFEST_HEADER_LINES = 3
$script:MANIFEST_TOKEN_PATTERN = '^token ([0-9a-f]{8})$'
$script:MANIFEST_EPOCH_PATTERN = '^epoch ([0-9]{1,12})$'
$script:MANIFEST_ITEM_PATTERN = '^([0-9]{1,4})\t([0-9]{1,18})\t([0-9]{1,18})\t([0-9]{1,18})\t(large-files|old-downloads)\t([^\t\r\n]+)$'
$script:MANIFEST_MAX_BYTES = 4194304
$script:MANIFEST_LINE_FEED = [char]10
$script:MANIFEST_FIELD_SEPARATOR = [char]9

function Test-ReviewNameSafe {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    foreach ($character in $Name.ToCharArray()) {
        if ([char]::IsControl($character)) { return $false }
        if ($script:REVIEW_UNSAFE_CHAR_CODES -contains [int]$character) { return $false }
    }
    return $true
}

function Test-ReviewBundleName {
    param([string]$Name)
    foreach ($suffix in $script:REVIEW_BUNDLE_SUFFIXES) {
        if ($Name.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-ReviewDirectoryPruned {
    param([string]$Name)
    if (Test-PrunedDirectoryName -Name $Name) { return $true }
    if ($script:REVIEW_PRUNED_DIR_NAMES -contains $Name) { return $true }
    return (Test-ReviewBundleName -Name $Name)
}

function Test-CloudPlaceholderAttribute {
    param([int]$Attributes)
    return (($Attributes -band $script:CLOUD_PLACEHOLDER_FLAGS) -ne 0)
}

# A file the user can see and that really holds data on this disk. Hidden and system
# files (the registry hive of the profile, desktop.ini) are never offered.
function Test-ReviewFileEligible {
    param([System.IO.FileInfo]$File)
    $attributes = [int]$File.Attributes
    if (($attributes -band $script:REPARSE_FLAG) -ne 0) { return $false }
    if (($attributes -band $script:DIRECTORY_FLAG) -ne 0) { return $false }
    if (($attributes -band $script:REVIEW_HIDDEN_FLAGS) -ne 0) { return $false }
    if (Test-CloudPlaceholderAttribute -Attributes $attributes) { return $false }
    return ([long]$File.Length -gt 0)
}

function Get-ReviewRoot {
    $homeRoot = Get-NormalizedPath -Path $env:USERPROFILE
    $stateRoot = Get-NormalizedPath -Path (Get-StateDirectory)
    if (($null -eq $homeRoot) -or ($null -eq $stateRoot)) { Invoke-CleanupFailure -Code 'INTERNAL' }
    $downloads = $null
    $candidate = [System.IO.Path]::Combine($homeRoot, $script:DOWNLOADS_DIR_NAME)
    if (Test-RealDirectory -Path $candidate) { $downloads = Get-NormalizedPath -Path $candidate }
    return [pscustomobject]@{ Home = $homeRoot; Downloads = $downloads; StateDir = $stateRoot }
}

# The review guard. A path may be listed, and later recycled, only when it is spelled
# exactly as Windows stores it (no short names, no dot segments), lies strictly inside
# the user profile, is not inside a pruned folder, a bundle or the state directory,
# and neither it nor any folder above it up to the profile is a link.
function Test-ReviewPathAllowed {
    param([string]$Path, $Roots)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    if ($Path.Length -ge $script:MAX_PATH_LENGTH) { return $false }
    $normalized = Get-NormalizedPath -Path $Path
    if ($null -eq $normalized) { return $false }
    if (-not $normalized.Equals($Path, [System.StringComparison]::Ordinal)) { return $false }
    if (-not (Test-PathInside -Child $Path -Parent $Roots.Home)) { return $false }
    if (Test-PathInside -Child $Path -Parent $Roots.StateDir) { return $false }
    $relative = $Path.Substring($Roots.Home.TrimEnd('\').Length).Trim('\')
    $segments = @($relative.Split('\'))
    $leafIndex = $segments.Count - 1
    for ($index = 0; $index -lt $leafIndex; $index++) {
        if (Test-ReviewDirectoryPruned -Name $segments[$index]) { return $false }
    }
    if (-not (Test-ReviewNameSafe -Name $segments[$leafIndex])) { return $false }
    return (Test-LinkFreeBelow -Target $Path -Root $Roots.Home)
}

function Test-ReviewDirectoryEntered {
    param([System.IO.DirectoryInfo]$Directory)
    if (Test-ReparsePoint -Info $Directory) { return $false }
    return (-not (Test-ReviewDirectoryPruned -Name $Directory.Name))
}

# Returns a candidate record for a file that belongs to a group, or nothing.
# large-files wins over old-downloads. Size is what the file occupies on disk.
function Get-ReviewFileRecord {
    param([System.IO.FileInfo]$File, [bool]$InDownloads, $Rule)
    if (-not (Test-ReviewFileEligible -File $File)) { return }
    if ($InDownloads -and (Test-SelectionFileName -Name $File.Name)) { return }
    $isOldDownload = $InDownloads -and ($File.LastWriteTimeUtc -le $Rule.DownloadsCutoff)
    if (([long]$File.Length -lt $Rule.MinBytes) -and (-not $isOldDownload)) { return }
    if ($File.FullName.Length -ge $script:MAX_PATH_LENGTH) { return }
    if (-not (Test-ReviewNameSafe -Name $File.Name)) { return }
    $allocated = Get-AllocatedFileSize -Path $File.FullName
    if ($null -eq $allocated) { $allocated = [long]$File.Length }
    if ([long]$allocated -le 0) { return }
    $group = $script:REVIEW_GROUP_DOWNLOADS
    if ([long]$allocated -ge $Rule.MinBytes) { $group = $script:REVIEW_GROUP_LARGE } elseif (-not $isOldDownload) { return }
    return [pscustomobject]@{
        Path       = [string]$File.FullName
        Size       = [long]$allocated
        Length     = [long]$File.Length
        MtimeTicks = [long]$File.LastWriteTimeUtc.Ticks
        Group      = $group
    }
}

# Read-only walk of the user profile. Links are never followed, so the walk also
# stays on the profile's volume. A folder that cannot be listed is skipped and noted.
function Get-ReviewCandidateList {
    param($Roots, $Rule)
    $found = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $denied = $false
    $stack = New-Object -TypeName System.Collections.Stack
    $stack.Push($Roots.Home)
    while ($stack.Count -gt 0) {
        $directory = [string]$stack.Pop()
        $listing = Get-ChildEntryList -Path $directory
        if ($listing.Failed) { $denied = $true }
        $inDownloads = $directory.Equals([string]$Roots.Downloads, [System.StringComparison]::OrdinalIgnoreCase)
        foreach ($entry in $listing.Entries) {
            try {
                if ($entry -is [System.IO.DirectoryInfo]) {
                    if (Test-ReviewDirectoryEntered -Directory $entry) { $stack.Push($entry.FullName) }
                    continue
                }
                $record = Get-ReviewFileRecord -File $entry -InDownloads $inDownloads -Rule $Rule
                if ($null -ne $record) { $found.Add($record) }
            } catch {
                $denied = $true
            }
        }
    }
    return [pscustomobject]@{ Candidates = $found.ToArray(); Denied = $denied }
}

# Largest first, at most REVIEW_MAX_ITEMS, numbered from 1. Every kept path has
# passed the same guard review-apply uses.
function Select-ReviewItem {
    param([object[]]$Candidates = @(), $Roots)
    $order = @(
        @{ Expression = 'Size'; Descending = $true },
        @{ Expression = 'Path'; Descending = $false }
    )
    $kept = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $truncated = $false
    foreach ($candidate in @($Candidates | Sort-Object -Property $order)) {
        if ($kept.Count -ge $script:REVIEW_MAX_ITEMS) {
            $truncated = $true
            break
        }
        if (-not (Test-ReviewPathAllowed -Path $candidate.Path -Roots $Roots)) { continue }
        $kept.Add([pscustomobject]@{
                Id         = $kept.Count + 1
                Path       = $candidate.Path
                Size       = $candidate.Size
                Length     = $candidate.Length
                MtimeTicks = $candidate.MtimeTicks
                Group      = $candidate.Group
            })
    }
    return [pscustomobject]@{ Items = $kept.ToArray(); Truncated = $truncated }
}

function Get-ReviewManifestPath {
    return [System.IO.Path]::Combine((Get-StateDirectory), $script:REVIEW_MANIFEST_NAME)
}

function Get-ReviewReportPath {
    return [System.IO.Path]::Combine((Get-StateDirectory), $script:REVIEW_REPORT_NAME)
}

function Write-ReviewStateFile {
    param([string]$Path, [string]$Text)
    $directory = Get-StateDirectory
    if ([string]::IsNullOrEmpty($directory)) { Invoke-CleanupFailure -Code 'INTERNAL' }
    if (Test-PathIsLinkIfPresent -Path $directory) { Invoke-CleanupFailure -Code 'INTERNAL' }
    if (Test-PathIsLinkIfPresent -Path $Path) { Invoke-CleanupFailure -Code 'INTERNAL' }
    [void][System.IO.Directory]::CreateDirectory($directory)
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

# One line per item: id, size on disk, length, modification time in ticks, group,
# absolute path. Names with a tab or a line break were never listed, so the format
# cannot be broken by a file name.
function ConvertTo-ManifestText {
    param([string]$Token, [object[]]$Items = @())
    $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $lines.Add($script:MANIFEST_HEADER)
    $lines.Add('token ' + $Token)
    $lines.Add('epoch ' + [string](Get-EpochSecond))
    foreach ($item in $Items) {
        $fields = @(
            [string]$item.Id, [string]$item.Size, [string]$item.Length, [string]$item.MtimeTicks,
            [string]$item.Group, [string]$item.Path
        )
        $lines.Add(($fields -join [string]$script:MANIFEST_FIELD_SEPARATOR))
    }
    return (($lines.ToArray() -join [string]$script:MANIFEST_LINE_FEED) + [string]$script:MANIFEST_LINE_FEED)
}

function ConvertFrom-ManifestLine {
    param([string]$Line)
    $found = [regex]::Match($Line, $script:MANIFEST_ITEM_PATTERN)
    if (-not $found.Success) { throw 'manifest line is malformed' }
    return [pscustomobject]@{
        Id         = [int]$found.Groups[1].Value
        Size       = [long]$found.Groups[2].Value
        Length     = [long]$found.Groups[3].Value
        MtimeTicks = [long]$found.Groups[4].Value
        Group      = [string]$found.Groups[5].Value
        Path       = [string]$found.Groups[6].Value
    }
}

# Parses the manifest text into a record. Throws on anything unexpected; the caller
# maps that to TOKEN_INVALID. Paths are data only: each one is checked again by the
# review guard before anything is done with it.
function ConvertFrom-ManifestText {
    param([string]$Text)
    $lines = @($Text.Split($script:MANIFEST_LINE_FEED) | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -lt $script:MANIFEST_HEADER_LINES) { throw 'manifest is too short' }
    if ([string]$lines[0] -cne $script:MANIFEST_HEADER) { throw 'manifest header is unknown' }
    $token = [regex]::Match([string]$lines[1], $script:MANIFEST_TOKEN_PATTERN)
    $epoch = [regex]::Match([string]$lines[2], $script:MANIFEST_EPOCH_PATTERN)
    if (-not ($token.Success -and $epoch.Success)) { throw 'manifest header is malformed' }
    $items = New-Object -TypeName 'System.Collections.Generic.Dictionary[int,object]'
    for ($index = $script:MANIFEST_HEADER_LINES; $index -lt $lines.Count; $index++) {
        $item = ConvertFrom-ManifestLine -Line ([string]$lines[$index])
        if ($items.ContainsKey($item.Id)) { throw 'manifest id is repeated' }
        $items.Add($item.Id, $item)
    }
    return [pscustomobject]@{
        Token = [string]$token.Groups[1].Value
        Epoch = [long]$epoch.Groups[1].Value
        Items = $items
    }
}

function Read-ReviewManifestFile {
    $path = Get-ReviewManifestPath
    try {
        if (-not [System.IO.File]::Exists($path)) { return $null }
        if (Test-PathIsLink -Path $path) { return $null }
        $file = New-Object -TypeName System.IO.FileInfo -ArgumentList $path
        if ([long]$file.Length -gt $script:MANIFEST_MAX_BYTES) { return $null }
        $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        return (ConvertFrom-ManifestText -Text ([System.IO.File]::ReadAllText($path, $encoding)))
    } catch {
        return $null
    }
}

# The review token lives in the manifest, apart from the scan state: a review does
# not invalidate a scan and a scan does not invalidate a review.
function Read-ReviewManifest {
    param([string]$Token)
    $manifest = Read-ReviewManifestFile
    if ($null -eq $manifest) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    if ($manifest.Token -cne $Token) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    $age = (Get-EpochSecond) - $manifest.Epoch
    if ($age -lt 0) { Invoke-CleanupFailure -Code 'TOKEN_INVALID' }
    if ($age -ge $script:REVIEW_TOKEN_TTL_SECONDS) { Invoke-CleanupFailure -Code 'TOKEN_EXPIRED' }
    return $manifest
}

function Get-ReviewGroupSummary {
    param([object[]]$Items = @())
    foreach ($group in $script:REVIEW_GROUPS) {
        $count = 0
        $bytes = [long]0
        foreach ($item in $Items) {
            if ($item.Group -ne $group['Id']) { continue }
            $count += 1
            $bytes += [long]$item.Size
        }
        [ordered]@{ id = $group['Id']; label = $group['Label']; item_count = $count; size_bytes = $bytes }
    }
}

function Get-ReviewDocument {
    param([string]$Token, $Selection, [bool]$Denied, [bool]$Opened)
    $groups = @(Get-ReviewGroupSummary -Items $Selection.Items)
    $totalCount = 0
    $totalBytes = [long]0
    foreach ($group in $groups) {
        $totalCount += [int]$group['item_count']
        $totalBytes += [long]$group['size_bytes']
    }
    $document = [ordered]@{
        schema_version           = $script:SCHEMA_VERSION
        command                  = $script:COMMAND_REVIEW
        platform                 = $script:PLATFORM_NAME
        token                    = $Token
        token_expires_in_seconds = $script:REVIEW_TOKEN_TTL_SECONDS
        groups                   = $groups
        total_item_count         = $totalCount
        total_size_bytes         = $totalBytes
        truncated                = $Selection.Truncated
        report_opened            = $Opened
        report_location_hint     = $script:REVIEW_REPORT_HINT
        selection_file_hint      = $script:REVIEW_SELECTION_HINT
    }
    if ($Denied) { $document['skipped_no_permission'] = $true }
    return $document
}

# Lists candidates for the user and writes the manifest plus the local report.
# Nothing is moved or deleted here, and no file or folder name reaches stdout.
function Invoke-ReviewCommand {
    param($Options)
    $roots = Get-ReviewRoot
    $rule = [pscustomobject]@{
        MinBytes        = [long]$Options.MinSizeMb * $script:BYTES_PER_MEGABYTE
        DownloadsCutoff = (Get-UtcNow).AddDays(-1 * $Options.DownloadsAgeDays)
    }
    $walk = Get-ReviewCandidateList -Roots $roots -Rule $rule
    $selection = Select-ReviewItem -Candidates $walk.Candidates -Roots $roots
    $token = Get-FreshToken
    $reportPath = Get-ReviewReportPath
    $report = Get-ReviewReportHtml -Token $token -Items $selection.Items -HomeRoot $roots.Home
    Write-ReviewStateFile -Path $reportPath -Text $report
    Write-ReviewStateFile -Path (Get-ReviewManifestPath) -Text (ConvertTo-ManifestText -Token $token -Items $selection.Items)
    $opened = ((Open-ReviewReport -Path $reportPath) -eq $true)
    return (Get-ReviewDocument -Token $token -Selection $selection -Denied $walk.Denied -Opened $opened)
}
