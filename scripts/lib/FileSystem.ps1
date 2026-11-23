$script:ABSOLUTE_PATH_PATTERN = '^[A-Za-z]:[\\/]'
$script:WILDCARD_CHARS = [char[]]@('*', '?')
$script:DRIVE_ROOT_LENGTH = 3
$script:MIN_HOME_DEPTH = 2
$script:REPARSE_FLAG = [int][System.IO.FileAttributes]::ReparsePoint
$script:READ_ONLY_FLAG = [int][System.IO.FileAttributes]::ReadOnly
$script:NORMAL_FLAG = [int][System.IO.FileAttributes]::Normal

function Test-ReparsePoint {
    param([System.IO.FileSystemInfo]$Info)
    return ((([int]$Info.Attributes) -band $script:REPARSE_FLAG) -ne 0)
}

function Test-PathIsLink {
    param([string]$Path)
    try {
        $attributes = [System.IO.File]::GetAttributes($Path)
    } catch {
        # Unreadable attributes are treated as a link so the caller refuses the path.
        return $true
    }
    return ((([int]$attributes) -band $script:REPARSE_FLAG) -ne 0)
}

function Test-RealDirectory {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    if (-not [System.IO.Directory]::Exists($Path)) { return $false }
    return (-not (Test-PathIsLink -Path $Path))
}

function Get-RealChildPath {
    param([string]$Parent, [string]$Name)
    $joined = [System.IO.Path]::Combine($Parent, $Name)
    try {
        $found = @([System.IO.Directory]::GetFileSystemEntries($Parent, $Name))
    } catch {
        return $joined
    }
    if ($found.Count -eq 1) { return [string]$found[0] }
    return $joined
}

# Resolves 8.3 short names and letter case segment by segment so that prefix
# comparisons against the allowed roots cannot be fooled by an alternate spelling.
function Get-NormalizedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ($Path -notmatch $script:ABSOLUTE_PATH_PATTERN) { return $null }
    if ($Path.IndexOfAny($script:WILDCARD_CHARS) -ge 0) { return $null }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $null
    }
    $current = $full.Substring(0, $script:DRIVE_ROOT_LENGTH)
    $remainder = $full.Substring($script:DRIVE_ROOT_LENGTH)
    foreach ($segment in $remainder.Split('\')) {
        if ($segment.Length -eq 0) { continue }
        $current = Get-RealChildPath -Parent $current -Name $segment
    }
    return $current
}

function Test-PathInside {
    param([string]$Child, [string]$Parent)
    $prefix = $Parent.TrimEnd('\') + '\'
    if ($Child.Length -le $prefix.Length) { return $false }
    return $Child.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativeDepth {
    param([string]$Child, [string]$Parent)
    $relative = $Child.Substring($Parent.TrimEnd('\').Length).Trim('\')
    return @($relative.Split('\')).Count
}

function Get-AllowedRootList {
    $roots = New-Object -TypeName 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA)) {
        $normalized = Get-NormalizedPath -Path $candidate
        if ($null -eq $normalized) { continue }
        if ($normalized.Length -le $script:DRIVE_ROOT_LENGTH) { continue }
        $roots.Add($normalized)
    }
    return $roots.ToArray()
}

function Test-LinkFreeBelow {
    param([string]$Target, [string]$Root)
    $current = $Target
    while ((-not [string]::IsNullOrEmpty($current)) -and (Test-PathInside -Child $current -Parent $Root)) {
        if (Test-PathIsLink -Path $current) { return $false }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
    return $true
}

function Get-ContainingRoot {
    param([string]$Target, [string[]]$Roots)
    $containing = $null
    foreach ($root in $Roots) {
        if (-not (Test-PathInside -Child $Target -Parent $root)) { continue }
        if (($null -eq $containing) -or ($root.Length -gt $containing.Length)) { $containing = $root }
    }
    return $containing
}

function Test-DeletionAllowed {
    param([string]$Path)
    $target = Get-NormalizedPath -Path $Path
    if ($null -eq $target) { return $false }
    $profileRoot = Get-NormalizedPath -Path $env:USERPROFILE
    if ($null -eq $profileRoot) { return $false }
    $roots = @(Get-AllowedRootList)
    foreach ($root in $roots) {
        if ($target.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    $containing = Get-ContainingRoot -Target $target -Roots $roots
    if ($null -eq $containing) { return $false }
    if (Test-PathInside -Child $target -Parent $profileRoot) {
        $depth = Get-RelativeDepth -Child $target -Parent $profileRoot
        if ($depth -lt $script:MIN_HOME_DEPTH) { return $false }
    }
    return (Test-LinkFreeBelow -Target $target -Root $containing)
}

function Get-CleanTarget {
    param(
        [string]$Path,
        [System.DateTime]$Cutoff = $script:NO_CUTOFF,
        [string[]]$ExcludeNames = @(),
        [string[]]$FilePatterns = @(),
        [bool]$KeepRoot = $true
    )
    return [pscustomobject]@{
        Path         = $Path
        Cutoff       = $Cutoff
        ExcludeNames = @($ExcludeNames)
        FilePatterns = @($FilePatterns)
        KeepRoot     = $KeepRoot
    }
}

function Get-ChildEntryList {
    param([string]$Path)
    try {
        $directory = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $Path
        $entries = @($directory.GetFileSystemInfos())
    } catch {
        return [pscustomobject]@{ Entries = @(); Failed = $true }
    }
    return [pscustomobject]@{ Entries = $entries; Failed = $false }
}

function Test-TopEntryIncluded {
    param([System.IO.FileSystemInfo]$Entry, $Target)
    if ($Target.ExcludeNames -contains $Entry.Name) { return $false }
    $patterns = @($Target.FilePatterns)
    if ($patterns.Count -eq 0) { return $true }
    if ($Entry -is [System.IO.DirectoryInfo]) { return $false }
    foreach ($pattern in $patterns) {
        if ($Entry.Name -like $pattern) { return $true }
    }
    return $false
}

function Get-TargetEntryList {
    param($Target)
    if ($Target.KeepRoot) {
        $listing = Get-ChildEntryList -Path $Target.Path
        $kept = @($listing.Entries | Where-Object { Test-TopEntryIncluded -Entry $_ -Target $Target })
        return [pscustomobject]@{ Entries = $kept; Failed = $listing.Failed }
    }
    try {
        if ([System.IO.File]::Exists($Target.Path)) {
            $root = New-Object -TypeName System.IO.FileInfo -ArgumentList $Target.Path
        } else {
            $root = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $Target.Path
        }
        $missing = -not $root.Exists
    } catch {
        return [pscustomobject]@{ Entries = @(); Failed = $true }
    }
    if ($missing) { return [pscustomobject]@{ Entries = @(); Failed = $true } }
    return [pscustomobject]@{ Entries = @($root); Failed = $false }
}

function Measure-Target {
    param($Target)
    $top = Get-TargetEntryList -Target $Target
    $bytes = [long]0
    $files = 0
    $denied = $top.Failed
    $stack = New-Object -TypeName System.Collections.Stack
    foreach ($entry in $top.Entries) { $stack.Push($entry) }
    while ($stack.Count -gt 0) {
        $entry = $stack.Pop()
        if (Test-ReparsePoint -Info $entry) { continue }
        if ($entry -is [System.IO.DirectoryInfo]) {
            $listing = Get-ChildEntryList -Path $entry.FullName
            if ($listing.Failed) { $denied = $true }
            foreach ($child in $listing.Entries) { $stack.Push($child) }
            continue
        }
        if ($entry.LastWriteTimeUtc -lt $Target.Cutoff) {
            $bytes += [long]$entry.Length
            $files += 1
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Files = $files; Denied = $denied }
}

# The only place in the script that removes anything from disk. Non-recursive on
# purpose: a directory is removed only after it has been emptied entry by entry, and
# a junction or symlink is removed as the link itself, never through to its target.
function Invoke-EntryDelete {
    param([System.IO.FileSystemInfo]$Info)
    try {
        $attributes = [int]$Info.Attributes
        if (($attributes -band $script:READ_ONLY_FLAG) -ne 0) {
            $cleared = $attributes -band (-bnot $script:READ_ONLY_FLAG)
            # An attribute value of 0 is not valid; a file with nothing set is Normal.
            if ($cleared -eq 0) { $cleared = $script:NORMAL_FLAG }
            $Info.Attributes = [System.IO.FileAttributes]$cleared
        }
        $Info.Delete()
    } catch {
        return $false
    }
    return $true
}

# Without an age cutoff everything below the target was meant to go, so a directory
# that is still not empty counts as a failure. With a cutoff, newer files stay on purpose.
function Invoke-EmptyDirectorySweep {
    param([System.IO.DirectoryInfo[]]$Directories, [System.DateTime]$Cutoff)
    $failed = 0
    $mustBeEmpty = ($Cutoff -eq $script:NO_CUTOFF)
    for ($index = $Directories.Count - 1; $index -ge 0; $index--) {
        $directory = $Directories[$index]
        if ($directory.LastWriteTimeUtc -ge $Cutoff) { continue }
        $remaining = Get-ChildEntryList -Path $directory.FullName
        if ($remaining.Failed -or (@($remaining.Entries).Count -gt 0)) {
            if ($mustBeEmpty) { $failed += 1 }
            continue
        }
        if (-not (Invoke-EntryDelete -Info $directory)) { $failed += 1 }
    }
    return $failed
}

function Get-DeleteOutcome {
    param([long]$FreedBytes = 0, [int]$DeletedFiles = 0, [int]$FailedCount = 0, [bool]$Refused = $false)
    return [pscustomobject]@{
        FreedBytes   = $FreedBytes
        DeletedFiles = $DeletedFiles
        FailedCount  = $FailedCount
        Refused      = $Refused
    }
}

# Removes a link found inside a target without touching what it points at.
# Returns the number of failures (0 or 1).
function Remove-LinkEntry {
    param([System.IO.FileSystemInfo]$Link, [System.DateTime]$Cutoff, $Sink)
    if ($Link.LastWriteTimeUtc -ge $Cutoff) { return 0 }
    if (-not (Invoke-EntryDelete -Info $Link)) { return 1 }
    if ($null -ne $Sink) { $Sink.Add($Link.FullName) }
    return 0
}

# Single guarded delete routine. Refuses anything Test-DeletionAllowed rejects, never
# follows a reparse point (a link inside the target is removed as a link, its target
# is left untouched), and reports failures instead of throwing.
function Invoke-GuardedDelete {
    param($Target, $Sink)
    if (-not (Test-DeletionAllowed -Path $Target.Path)) { return (Get-DeleteOutcome -Refused $true) }
    $top = Get-TargetEntryList -Target $Target
    $freed = [long]0
    $deleted = 0
    $failed = 0
    if ($top.Failed) { $failed += 1 }
    $directories = New-Object -TypeName 'System.Collections.Generic.List[System.IO.DirectoryInfo]'
    $stack = New-Object -TypeName System.Collections.Stack
    foreach ($entry in $top.Entries) { $stack.Push($entry) }
    while ($stack.Count -gt 0) {
        $entry = $stack.Pop()
        if (Test-ReparsePoint -Info $entry) {
            $failed += Remove-LinkEntry -Link $entry -Cutoff $Target.Cutoff -Sink $Sink
            continue
        }
        if ($entry -is [System.IO.DirectoryInfo]) {
            $directories.Add($entry)
            $listing = Get-ChildEntryList -Path $entry.FullName
            if ($listing.Failed) { $failed += 1 }
            foreach ($child in $listing.Entries) { $stack.Push($child) }
            continue
        }
        if ($entry.LastWriteTimeUtc -ge $Target.Cutoff) { continue }
        $length = [long]$entry.Length
        if (-not (Invoke-EntryDelete -Info $entry)) { $failed += 1; continue }
        $freed += $length
        $deleted += 1
        if ($null -ne $Sink) { $Sink.Add($entry.FullName) }
    }
    $failed += Invoke-EmptyDirectorySweep -Directories ($directories.ToArray()) -Cutoff $Target.Cutoff
    return (Get-DeleteOutcome -FreedBytes $freed -DeletedFiles $deleted -FailedCount $failed)
}
