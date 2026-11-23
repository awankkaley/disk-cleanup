# The selection file is written by the browser, so it is untrusted input: it is read
# with a size cap and matched against one strict pattern. It is never parsed as JSON,
# never evaluated and never used as anything but a token, a secret and a list of
# numbers. The secret exists only in the manifest and in the report page, so a
# selection that carries it was saved from that page.
$script:SELECTION_NAME_PATTERN = '\Adisk-cleanup-selection(?: \([0-9]{1,3}\)|[- ][0-9]{1,3})?\.json\z'
$script:SELECTION_CONTENT_PATTERN = '\A\s*\{\s*"token"\s*:\s*"([0-9a-f]{8})"\s*,\s*"secret"\s*:\s*"([0-9a-f]{32})"\s*,\s*"ids"\s*:\s*\[\s*([0-9]{1,6}(?:\s*,\s*[0-9]{1,6})*)?\s*\]\s*\}\s*\z'
$script:SELECTION_MAX_BYTES = 1048576
$script:BYTE_ORDER_MARK = [char]65279

$script:TRASH_CHANGED = 'changed'

function Test-SelectionFileName {
    param([string]$Name)
    return [regex]::IsMatch([string]$Name, $script:SELECTION_NAME_PATTERN)
}

# The folders a browser saves the selection into: Downloads, or the Desktop when
# it asked the user where to save. A folder that is missing or is a link is not
# searched (Get-ReviewRoot leaves it $null).
function Get-SelectionFolderList {
    param($Roots)
    return @(foreach ($folder in @([string]$Roots.Downloads, [string]$Roots.Desktop)) {
            if (-not [string]::IsNullOrEmpty($folder)) { $folder }
        })
}

# Regular, non-link files directly inside the selection folders with a selection
# file name, newest first across all of them.
function Get-SelectionCandidateList {
    param($Roots)
    $files = @(foreach ($folder in @(Get-SelectionFolderList -Roots $Roots)) {
            $listing = Get-ChildEntryList -Path $folder
            foreach ($entry in $listing.Entries) {
                if (-not ($entry -is [System.IO.FileInfo])) { continue }
                if (Test-ReparsePoint -Info $entry) { continue }
                if (Test-SelectionFileName -Name $entry.Name) { $entry }
            }
        })
    return @($files | Sort-Object -Property LastWriteTimeUtc -Descending)
}

# Reads at most SELECTION_MAX_BYTES + 1 bytes, so a file that grows while it is
# being read is still rejected. Returns $null for anything larger or unreadable.
function Read-LimitedFileText {
    param([string]$Path)
    $limit = $script:SELECTION_MAX_BYTES + 1
    $buffer = New-Object -TypeName byte[] -ArgumentList $limit
    $total = 0
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            while ($total -lt $limit) {
                $read = $stream.Read($buffer, $total, $limit - $total)
                if ($read -le 0) { break }
                $total += $read
            }
        } finally {
            $stream.Dispose()
        }
    } catch {
        return $null
    }
    if ($total -gt $script:SELECTION_MAX_BYTES) { return $null }
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    return $encoding.GetString($buffer, 0, $total).TrimStart($script:BYTE_ORDER_MARK)
}

# Returns the token, the secret and the distinct ids of a well-formed selection
# file, or $null.
function Read-SelectionFile {
    param([System.IO.FileInfo]$File)
    $text = Read-LimitedFileText -Path $File.FullName
    if ($null -eq $text) { return $null }
    $found = [regex]::Match($text, $script:SELECTION_CONTENT_PATTERN)
    if (-not $found.Success) { return $null }
    $ids = New-Object -TypeName 'System.Collections.Generic.List[int]'
    if ($found.Groups[3].Success) {
        foreach ($part in $found.Groups[3].Value.Split(',')) {
            $id = [int]$part.Trim()
            if (-not $ids.Contains($id)) { $ids.Add($id) }
        }
    }
    return [pscustomobject]@{
        Token  = [string]$found.Groups[1].Value
        Secret = [string]$found.Groups[2].Value
        Ids    = $ids.ToArray()
    }
}

# A selection belongs to a review only when it carries both the token and the
# selection secret of that review.
function Test-SelectionOfReview {
    param($Selection, $Manifest)
    if ($null -eq $Selection) { return $false }
    if ([string]$Selection.Token -cne [string]$Manifest.Token) { return $false }
    return ([string]$Selection.Secret -ceq [string]$Manifest.Secret)
}

# The newest well-formed selection file that carries this review's token and secret.
function Find-ReviewSelection {
    param($Roots, $Manifest)
    $candidates = @(Get-SelectionCandidateList -Roots $Roots)
    if ($candidates.Count -eq 0) { Invoke-CleanupFailure -Code 'SELECTION_NOT_FOUND' }
    foreach ($candidate in $candidates) {
        $selection = Read-SelectionFile -File $candidate
        if (Test-SelectionOfReview -Selection $selection -Manifest $Manifest) { return $selection }
    }
    Invoke-CleanupFailure -Code 'SELECTION_INVALID'
}

# The manifest only names candidates. The rule of the item's group is applied again
# to the file itself, so a line that was added for some other file is refused:
# large-files must still occupy the minimum size, old-downloads must sit directly
# inside Downloads and still be older than the threshold.
function Test-ReviewItemInRule {
    param($Item, [System.IO.FileInfo]$File, $Roots, $Rule)
    $path = [string]$Item.Path
    if ([string]$Item.Group -ceq $script:REVIEW_GROUP_LARGE) {
        $allocated = Get-AllocatedFileSize -Path $path
        if ($null -eq $allocated) { $allocated = [long]$File.Length }
        return ([long]$allocated -ge [long]$Rule.MinBytes)
    }
    if ([string]$Item.Group -cne $script:REVIEW_GROUP_DOWNLOADS) { return $false }
    if ([string]::IsNullOrEmpty([string]$Roots.Downloads)) { return $false }
    $cut = $path.LastIndexOf('\')
    if ($cut -lt 0) { return $false }
    $parent = $path.Substring(0, $cut)
    if (-not $parent.Equals([string]$Roots.Downloads, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return ($File.LastWriteTimeUtc -le $Rule.DownloadsCutoff)
}

# Re-checks one manifest entry immediately before it is recycled: the path passes
# the review guard, the file is still the same regular file (same length, same
# modification time, not a link, not a cloud placeholder) and it still falls under
# the rule of its group.
function Test-ReviewItemUnchanged {
    param($Item, $Roots, $Rule)
    try {
        if (-not (Test-ReviewPathAllowed -Path ([string]$Item.Path) -Roots $Roots)) { return $false }
        $file = New-Object -TypeName System.IO.FileInfo -ArgumentList ([string]$Item.Path)
        if (-not $file.Exists) { return $false }
        if (-not (Test-ReviewFileEligible -File $file)) { return $false }
        if ([long]$file.Length -ne [long]$Item.Length) { return $false }
        if ([long]$file.LastWriteTimeUtc.Ticks -ne [long]$Item.MtimeTicks) { return $false }
        return ((Test-ReviewItemInRule -Item $Item -File $file -Roots $Roots -Rule $Rule) -eq $true)
    } catch {
        return $false
    }
}

# Returns trashed, changed, denied or failed. The file is handed to the Recycle Bin
# only when it is unchanged and the bin can hold it; otherwise it stays where it is.
function Invoke-ReviewItemTrash {
    param($Item, $Roots, $Rule)
    if (-not (Test-ReviewItemUnchanged -Item $Item -Roots $Roots -Rule $Rule)) { return $script:TRASH_CHANGED }
    if (-not ((Test-RecycleBinCanHold -Path ([string]$Item.Path) -Bytes ([long]$Item.Length)) -eq $true)) {
        return $script:RECYCLE_FAILED
    }
    $result = [string](Send-FileToRecycleBin -Path ([string]$Item.Path))
    if ($result -eq $script:RECYCLE_DENIED) { return $script:RECYCLE_DENIED }
    if ($result -ne $script:RECYCLE_TRASHED) { return $script:RECYCLE_FAILED }
    if ([System.IO.File]::Exists([string]$Item.Path)) { return $script:RECYCLE_FAILED }
    return $script:RECYCLE_TRASHED
}

function Invoke-ReviewSelectionTrash {
    param([int[]]$Ids = @(), $Manifest, $Roots, $Rule)
    $tally = @{ trashed = 0; changed = 0; denied = 0; failed = 0; ignored = 0 }
    $bytes = [long]0
    foreach ($id in $Ids) {
        if (-not $Manifest.Items.ContainsKey($id)) {
            $tally['ignored'] += 1
            continue
        }
        $item = $Manifest.Items[$id]
        try {
            $result = [string](Invoke-ReviewItemTrash -Item $item -Roots $Roots -Rule $Rule)
        } catch {
            $result = $script:RECYCLE_FAILED
        }
        if (-not $tally.ContainsKey($result)) { $result = $script:RECYCLE_FAILED }
        $tally[$result] += 1
        if ($result -eq $script:RECYCLE_TRASHED) { $bytes += [long]$item.Size }
    }
    return [pscustomobject]@{ Counts = $tally; Bytes = $bytes }
}

# Burns the single-use review token. The manifest is the tool's own file and goes
# through the guarded delete like every other removal.
function Clear-ReviewManifest {
    $target = Get-CleanTarget -Path (Get-ReviewManifestPath) -KeepRoot $false
    $outcome = Invoke-GuardedDelete -Target $target -Sink $null
    if ($outcome.DeletedFiles -ne 1) { Invoke-CleanupFailure -Code 'INTERNAL' }
}

# Removes the report and the selection files of this review. A file in Downloads or
# on the Desktop is removed only when it is one of the tool's own selection files:
# right name, regular file, well-formed content and this review's token and secret
# inside. Anything else stays.
function Clear-ReviewLeftover {
    param($Roots, $Manifest)
    $paths = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $reportPath = Get-ReviewReportPath
    if ([System.IO.File]::Exists($reportPath)) { $paths.Add($reportPath) }
    foreach ($candidate in @(Get-SelectionCandidateList -Roots $Roots)) {
        $selection = Read-SelectionFile -File $candidate
        if (Test-SelectionOfReview -Selection $selection -Manifest $Manifest) { $paths.Add([string]$candidate.FullName) }
    }
    foreach ($path in $paths.ToArray()) {
        $null = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $path -KeepRoot $false) -Sink $null
    }
}

function Get-ReviewApplyDocument {
    param([int]$SelectedCount, $Outcome, $Before, $After)
    $counts = $Outcome.Counts
    return [ordered]@{
        schema_version                 = $script:SCHEMA_VERSION
        command                        = $script:COMMAND_REVIEW_APPLY
        platform                       = $script:PLATFORM_NAME
        selected_count                 = $SelectedCount
        trashed_count                  = [int]$counts['trashed']
        trashed_bytes                  = [long]$Outcome.Bytes
        skipped_changed_count          = [int]$counts['changed']
        skipped_no_permission_count    = [int]$counts['denied']
        failed_count                   = [int]$counts['failed']
        ignored_count                  = [int]$counts['ignored']
        disk_before                    = [ordered]@{ free_bytes = $Before.FreeBytes }
        disk_after                     = [ordered]@{ free_bytes = $After.FreeBytes }
        space_freed_when_trash_emptied = $true
    }
}

# Moves the files the user ticked to the Recycle Bin. A manifest that no longer
# matches its digest is refused before anything is looked up or moved. The token is
# burned before anything is moved, so a run that is interrupted cannot be repeated.
function Invoke-ReviewApplyCommand {
    param($Options, [string]$ExpiredToken = '')
    $manifest = Read-ReviewManifest -Token $Options.Token -ExpiredToken $ExpiredToken
    if (-not ($manifest.IntegrityOk -eq $true)) { Invoke-CleanupFailure -Code 'SELECTION_INVALID' }
    $roots = Get-ReviewRoot
    $selection = Find-ReviewSelection -Roots $roots -Manifest $manifest
    $ids = [int[]]@($selection.Ids)
    $rule = Get-ReviewRule -MinSizeMb $manifest.MinSizeMb -DownloadsAgeDays $manifest.DownloadsAgeDays
    Clear-ReviewManifest
    $before = Get-DiskInfo
    $outcome = Invoke-ReviewSelectionTrash -Ids $ids -Manifest $manifest -Roots $roots -Rule $rule
    Clear-ReviewLeftover -Roots $roots -Manifest $manifest
    $after = Get-DiskInfo
    return (Get-ReviewApplyDocument -SelectedCount $ids.Count -Outcome $outcome -Before $before -After $after)
}
