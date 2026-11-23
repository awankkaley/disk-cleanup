# The selection file is written by the browser, so it is untrusted input: it is read
# with a size cap and matched against one strict pattern. It is never parsed as JSON,
# never evaluated and never used as anything but a token and a list of numbers.
$script:SELECTION_NAME_PATTERN = '\Adisk-cleanup-selection(?: \([0-9]{1,3}\)|-[0-9]{1,3})?\.json\z'
$script:SELECTION_CONTENT_PATTERN = '\A\s*\{\s*"token"\s*:\s*"([0-9a-f]{8})"\s*,\s*"ids"\s*:\s*\[\s*([0-9]{1,6}(?:\s*,\s*[0-9]{1,6})*)?\s*\]\s*\}\s*\z'
$script:SELECTION_MAX_BYTES = 1048576
$script:BYTE_ORDER_MARK = [char]65279

$script:TRASH_CHANGED = 'changed'

function Test-SelectionFileName {
    param([string]$Name)
    return [regex]::IsMatch([string]$Name, $script:SELECTION_NAME_PATTERN)
}

# Regular, non-link files directly inside Downloads with a selection file name,
# newest first.
function Get-SelectionCandidateList {
    param([string]$Downloads)
    if ([string]::IsNullOrEmpty($Downloads)) { return }
    $listing = Get-ChildEntryList -Path $Downloads
    $files = @(foreach ($entry in $listing.Entries) {
            if (-not ($entry -is [System.IO.FileInfo])) { continue }
            if (Test-ReparsePoint -Info $entry) { continue }
            if (Test-SelectionFileName -Name $entry.Name) { $entry }
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

# Returns the token and the distinct ids of a well-formed selection file, or $null.
function Read-SelectionFile {
    param([System.IO.FileInfo]$File)
    $text = Read-LimitedFileText -Path $File.FullName
    if ($null -eq $text) { return $null }
    $found = [regex]::Match($text, $script:SELECTION_CONTENT_PATTERN)
    if (-not $found.Success) { return $null }
    $ids = New-Object -TypeName 'System.Collections.Generic.List[int]'
    if ($found.Groups[2].Success) {
        foreach ($part in $found.Groups[2].Value.Split(',')) {
            $id = [int]$part.Trim()
            if (-not $ids.Contains($id)) { $ids.Add($id) }
        }
    }
    return [pscustomobject]@{ Token = [string]$found.Groups[1].Value; Ids = $ids.ToArray() }
}

# The newest well-formed selection file that carries this review's token.
function Find-ReviewSelection {
    param($Roots, [string]$Token)
    $candidates = @(Get-SelectionCandidateList -Downloads $Roots.Downloads)
    if ($candidates.Count -eq 0) { Invoke-CleanupFailure -Code 'SELECTION_NOT_FOUND' }
    foreach ($candidate in $candidates) {
        $selection = Read-SelectionFile -File $candidate
        if ($null -eq $selection) { continue }
        if ($selection.Token -ceq $Token) { return $selection }
    }
    Invoke-CleanupFailure -Code 'SELECTION_INVALID'
}

# Re-checks one manifest entry immediately before it is recycled: the path passes
# the review guard, and the file is still the same regular file (same length, same
# modification time, not a link, not a cloud placeholder).
function Test-ReviewItemUnchanged {
    param($Item, $Roots)
    try {
        if (-not (Test-ReviewPathAllowed -Path ([string]$Item.Path) -Roots $Roots)) { return $false }
        $file = New-Object -TypeName System.IO.FileInfo -ArgumentList ([string]$Item.Path)
        if (-not $file.Exists) { return $false }
        if (-not (Test-ReviewFileEligible -File $file)) { return $false }
        if ([long]$file.Length -ne [long]$Item.Length) { return $false }
        return ([long]$file.LastWriteTimeUtc.Ticks -eq [long]$Item.MtimeTicks)
    } catch {
        return $false
    }
}

# Returns trashed, changed, denied or failed. The file is handed to the Recycle Bin
# only when it is unchanged and the bin can hold it; otherwise it stays where it is.
function Invoke-ReviewItemTrash {
    param($Item, $Roots)
    if (-not (Test-ReviewItemUnchanged -Item $Item -Roots $Roots)) { return $script:TRASH_CHANGED }
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
    param([int[]]$Ids = @(), $Manifest, $Roots)
    $tally = @{ trashed = 0; changed = 0; denied = 0; failed = 0; ignored = 0 }
    $bytes = [long]0
    foreach ($id in $Ids) {
        if (-not $Manifest.Items.ContainsKey($id)) {
            $tally['ignored'] += 1
            continue
        }
        $item = $Manifest.Items[$id]
        try {
            $result = [string](Invoke-ReviewItemTrash -Item $item -Roots $Roots)
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

# Removes the report and the selection files of this review. A file in Downloads is
# removed only when it is one of the tool's own selection files: right name, regular
# file, well-formed content and this review's token inside. Anything else stays.
function Clear-ReviewLeftover {
    param($Roots, [string]$Token)
    $paths = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $reportPath = Get-ReviewReportPath
    if ([System.IO.File]::Exists($reportPath)) { $paths.Add($reportPath) }
    foreach ($candidate in @(Get-SelectionCandidateList -Downloads $Roots.Downloads)) {
        $selection = Read-SelectionFile -File $candidate
        if ($null -eq $selection) { continue }
        if ($selection.Token -ceq $Token) { $paths.Add([string]$candidate.FullName) }
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

# Moves the files the user ticked to the Recycle Bin. The token is burned before
# anything is moved, so a run that is interrupted cannot be repeated.
function Invoke-ReviewApplyCommand {
    param($Options)
    $manifest = Read-ReviewManifest -Token $Options.Token
    $roots = Get-ReviewRoot
    $selection = Find-ReviewSelection -Roots $roots -Token $Options.Token
    $ids = [int[]]@($selection.Ids)
    Clear-ReviewManifest
    $before = Get-DiskInfo
    $outcome = Invoke-ReviewSelectionTrash -Ids $ids -Manifest $manifest -Roots $roots
    Clear-ReviewLeftover -Roots $roots -Token $Options.Token
    $after = Get-DiskInfo
    return (Get-ReviewApplyDocument -SelectedCount $ids.Count -Outcome $outcome -Before $before -After $after)
}
