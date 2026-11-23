$script:NODE_MODULES_DIR = 'node_modules'
$script:PACKAGE_MANIFEST = 'package.json'
$script:LOCKFILE_NAMES = @('package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lock', 'bun.lockb')
$script:GIT_DIR = '.git'
$script:GIT_ACTIVITY_FILES = @('index', 'HEAD')
$script:PRUNED_DIR_NAMES = @('Library', 'AppData')
$script:HIDDEN_DIR_PREFIX = '.'
$script:UNKNOWN_IDLE_DAYS = -1
$script:NPM_TOOL = 'npm'
$script:NPM_GLOBAL_ROOT_ARGUMENTS = @('root', '-g')
$script:NPM_SCOPE_PREFIX = '@'
$script:IDLE_BUCKETS = @(
    @{ Id = '30-90'; MinIdleDays = 30; MaxIdleDays = 90 },
    @{ Id = '90-180'; MinIdleDays = 90; MaxIdleDays = 180 },
    @{ Id = '180+'; MinIdleDays = 180; MaxIdleDays = [int]::MaxValue }
)

function Test-PrunedDirectoryName {
    param([string]$Name)
    if ($Name.StartsWith($script:HIDDEN_DIR_PREFIX)) { return $true }
    if ($Name -eq $script:NODE_MODULES_DIR) { return $true }
    return ($script:PRUNED_DIR_NAMES -contains $Name)
}

# Read-only walk that returns every directory owning a real node_modules folder.
# It never descends into node_modules, dot-directories, Library or AppData.
function Find-NodeModulesProject {
    param([string]$Root)
    $stack = New-Object -TypeName System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $directory = [string]$stack.Pop()
        $listing = Get-ChildEntryList -Path $directory
        foreach ($entry in $listing.Entries) {
            if (-not ($entry -is [System.IO.DirectoryInfo])) { continue }
            if (Test-ReparsePoint -Info $entry) { continue }
            if ($entry.Name -eq $script:NODE_MODULES_DIR) { $directory; continue }
            if (Test-PrunedDirectoryName -Name $entry.Name) { continue }
            $stack.Push($entry.FullName)
        }
    }
}

function Test-ProjectManifest {
    param([string]$ProjectDir)
    $manifest = [System.IO.Path]::Combine($ProjectDir, $script:PACKAGE_MANIFEST)
    if (-not [System.IO.File]::Exists($manifest)) { return $false }
    foreach ($name in $script:LOCKFILE_NAMES) {
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($ProjectDir, $name))) { return $true }
    }
    return $false
}

function Get-GitActivityTime {
    param([string]$GitDir)
    $latest = [System.DateTime]::MinValue
    foreach ($name in $script:GIT_ACTIVITY_FILES) {
        $file = [System.IO.Path]::Combine($GitDir, $name)
        if (-not [System.IO.File]::Exists($file)) { continue }
        $stamp = [System.IO.File]::GetLastWriteTimeUtc($file)
        if ($stamp -gt $latest) { $latest = $stamp }
    }
    return $latest
}

# Newest modification time of the project's own files: node_modules is ignored and
# of .git only index and HEAD count. Returns $null when a folder cannot be read,
# so an unreadable project is treated as active.
function Get-ProjectActivityTime {
    param([string]$ProjectDir)
    $latest = [System.DateTime]::MinValue
    $stack = New-Object -TypeName System.Collections.Stack
    $stack.Push($ProjectDir)
    while ($stack.Count -gt 0) {
        $listing = Get-ChildEntryList -Path ([string]$stack.Pop())
        if ($listing.Failed) { return $null }
        foreach ($entry in $listing.Entries) {
            if (Test-ReparsePoint -Info $entry) { continue }
            $stamp = [System.DateTime]::MinValue
            if (-not ($entry -is [System.IO.DirectoryInfo])) {
                $stamp = $entry.LastWriteTimeUtc
            } elseif ($entry.Name -eq $script:GIT_DIR) {
                $stamp = Get-GitActivityTime -GitDir $entry.FullName
            } elseif ($entry.Name -ne $script:NODE_MODULES_DIR) {
                $stack.Push($entry.FullName)
            }
            if ($stamp -gt $latest) { $latest = $stamp }
        }
    }
    return $latest
}

function Get-ProjectIdleDay {
    param([string]$ProjectDir, [System.DateTime]$NowUtc)
    $latest = Get-ProjectActivityTime -ProjectDir $ProjectDir
    if ($null -eq $latest) { return $script:UNKNOWN_IDLE_DAYS }
    if ($latest -eq [System.DateTime]::MinValue) { return $script:UNKNOWN_IDLE_DAYS }
    return [int][System.Math]::Floor(($NowUtc - $latest).TotalDays)
}

# Entries of the global npm folder, including those one level down inside a scope.
function Get-GlobalPackageEntryList {
    param([string]$Root)
    foreach ($entry in (Get-ChildEntryList -Path $Root).Entries) {
        $entry
        if (Test-ReparsePoint -Info $entry) { continue }
        if (-not $entry.Name.StartsWith($script:NPM_SCOPE_PREFIX)) { continue }
        foreach ($scoped in (Get-ChildEntryList -Path $entry.FullName).Entries) { $scoped }
    }
}

# Project folders that 'npm link' exposes as global tools: their node_modules is in
# use even when the project itself has been idle. Read-only, and only when npm exists
# and reports its global folder.
function Get-GlobalLinkTargetList {
    if ($null -eq (Get-ToolPath -Name $script:NPM_TOOL)) { return }
    $answer = Get-ToolReportedPath -Tool $script:NPM_TOOL -Arguments $script:NPM_GLOBAL_ROOT_ARGUMENTS
    if (-not (Test-RealDirectory -Path $answer.Path)) { return }
    foreach ($entry in @(Get-GlobalPackageEntryList -Root $answer.Path)) {
        if (-not (Test-ReparsePoint -Info $entry)) { continue }
        Get-LinkTargetPath -Link $entry
    }
}

# Emits one record per node_modules folder that satisfies every eligibility rule,
# passes the delete guard and has been idle for at least the minimum threshold.
function Get-StaleProjectList {
    param($Context, [int]$MinIdleDays)
    $linkedProjects = @(Get-GlobalLinkTargetList)
    foreach ($projectDir in @(Find-NodeModulesProject -Root $Context.ProjectsRoot)) {
        if (-not (Test-ProjectManifest -ProjectDir $projectDir)) { continue }
        if ($linkedProjects -contains $projectDir) { continue }
        $idleDays = Get-ProjectIdleDay -ProjectDir $projectDir -NowUtc $Context.NowUtc
        if ($idleDays -lt $MinIdleDays) { continue }
        $modulesDir = [System.IO.Path]::Combine($projectDir, $script:NODE_MODULES_DIR)
        if (-not (Test-DeletionAllowed -Path $modulesDir)) { continue }
        [pscustomobject]@{
            IdleDays = $idleDays
            Target   = (Get-CleanTarget -Path $modulesDir -KeepRoot $false)
        }
    }
}

function Get-IdleBucketList {
    param([object[]]$Sized)
    foreach ($bucket in $script:IDLE_BUCKETS) {
        $count = 0
        $bytes = [long]0
        foreach ($project in $Sized) {
            if ($project.IdleDays -lt $bucket['MinIdleDays']) { continue }
            if ($project.IdleDays -ge $bucket['MaxIdleDays']) { continue }
            $count += 1
            $bytes += $project.Bytes
        }
        [ordered]@{
            id            = $bucket['Id']
            min_idle_days = $bucket['MinIdleDays']
            project_count = $count
            size_bytes    = $bytes
        }
    }
}

function Get-NodeModulesScan {
    param($Context)
    $projects = @(Get-StaleProjectList -Context $Context -MinIdleDays $script:MIN_IDLE_DAYS_FLOOR)
    $sized = @(foreach ($project in $projects) {
            [pscustomobject]@{ IdleDays = $project.IdleDays; Bytes = (Measure-Target -Target $project.Target).Bytes }
        })
    $total = [long]0
    foreach ($item in $sized) { $total += $item.Bytes }
    $buckets = @(Get-IdleBucketList -Sized $sized)
    $status = 'empty'
    if ($sized.Count -gt 0) { $status = 'ok' }
    return (Get-ScanMeasure -Status $status -Bytes $total -Files $sized.Count -Buckets $buckets)
}

function Invoke-NodeModulesClean {
    param($Context)
    $projects = @(Get-StaleProjectList -Context $Context -MinIdleDays $Context.MinIdleDays)
    if ($projects.Count -eq 0) { return (Get-CleanState -Status 'not_found') }
    $targets = @($projects | ForEach-Object { $_.Target })
    return (Invoke-TargetListClean -Targets $targets -Sink $Context.Sink)
}
