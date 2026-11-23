function Get-CleanPlan {
    param([object[]]$Targets = @(), [bool]$Installed = $false, [bool]$Running = $false)
    return [pscustomobject]@{ Targets = @($Targets); Installed = $Installed; Running = $Running }
}

function Get-SegmentMatchList {
    param([string]$Directory, [string]$Segment)
    if (-not $Segment.Contains('*')) {
        $candidate = [System.IO.Path]::Combine($Directory, $Segment)
        if (Test-RealDirectory -Path $candidate) { return $candidate }
        return
    }
    $listing = Get-ChildEntryList -Path $Directory
    foreach ($entry in $listing.Entries) {
        if (-not ($entry -is [System.IO.DirectoryInfo])) { continue }
        if (Test-ReparsePoint -Info $entry) { continue }
        if ($entry.Name -like $Segment) { $entry.FullName }
    }
}

# Expands a relative pattern such as 'Packages\*\TempState' below a root into the
# existing real directories it names. A '*' matches within one path segment only.
function Resolve-DirectoryPattern {
    param([string]$Root, [string]$Pattern)
    if ([string]::IsNullOrEmpty($Root)) { return }
    $current = @($Root)
    foreach ($segment in $Pattern.Split('\')) {
        $next = New-Object -TypeName 'System.Collections.Generic.List[string]'
        foreach ($directory in $current) {
            foreach ($found in @(Get-SegmentMatchList -Directory $directory -Segment $segment)) {
                $next.Add([string]$found)
            }
        }
        $current = @($next.ToArray())
    }
    return $current
}

function Get-AppCachePlan {
    $targets = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $installed = $false
    $running = $false
    foreach ($app in $script:KNOWN_APP_CACHES) {
        $appDir = Join-BasePath -Base $app['Base'] -Relative $app['Path']
        if (-not (Test-RealDirectory -Path $appDir)) { continue }
        $installed = $true
        if (Test-AppRunning -Names $app['Processes']) {
            $running = $true
            continue
        }
        foreach ($name in $script:APP_CACHE_DIR_NAMES) {
            $cacheDir = [System.IO.Path]::Combine($appDir, $name)
            if (Test-RealDirectory -Path $cacheDir) { $targets.Add((Get-CleanTarget -Path $cacheDir)) }
        }
    }
    return (Get-CleanPlan -Targets ($targets.ToArray()) -Installed $installed -Running $running)
}

function Get-BrowserProfileList {
    param([string]$UserData, $Browser)
    if ($Browser['RootIsProfile']) { $UserData }
    $listing = Get-ChildEntryList -Path $UserData
    foreach ($entry in $listing.Entries) {
        if (-not ($entry -is [System.IO.DirectoryInfo])) { continue }
        if (Test-ReparsePoint -Info $entry) { continue }
        if ($entry.Name -match $Browser['ProfilePattern']) { $entry.FullName }
    }
}

function Get-BrowserPlan {
    param($Browser)
    $userDataDirs = @(foreach ($root in $Browser['Roots']) {
            Resolve-DirectoryPattern -Root (Get-BasePath -Base $root['Base']) -Pattern $root['Path']
        })
    if ($userDataDirs.Count -eq 0) { return (Get-CleanPlan) }
    if (Test-AppRunning -Names $Browser['Processes']) { return (Get-CleanPlan -Installed $true -Running $true) }
    $targets = New-Object -TypeName 'System.Collections.Generic.List[object]'
    foreach ($userData in $userDataDirs) {
        foreach ($profileDir in @(Get-BrowserProfileList -UserData $userData -Browser $Browser)) {
            foreach ($name in $Browser['CacheNames']) {
                $cacheDir = [System.IO.Path]::Combine($profileDir, $name)
                if (Test-RealDirectory -Path $cacheDir) { $targets.Add((Get-CleanTarget -Path $cacheDir)) }
            }
        }
    }
    return (Get-CleanPlan -Targets ($targets.ToArray()) -Installed $true)
}

# A package with an open process is skipped as a whole; the others are still cleaned.
function Get-StoreAppPlan {
    $packageRoot = Join-BasePath -Base 'Local' -Relative $script:STORE_PACKAGE_ROOT
    if (-not (Test-RealDirectory -Path $packageRoot)) { return (Get-CleanPlan) }
    $runningFamilies = @(Get-RunningPackageFamilyList)
    $targets = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $running = $false
    foreach ($package in @(Get-SegmentMatchList -Directory $packageRoot -Segment '*')) {
        $caches = @(foreach ($relative in $script:STORE_APP_CACHE_SUBPATHS) {
                Resolve-DirectoryPattern -Root $package -Pattern $relative
            })
        if ($caches.Count -eq 0) { continue }
        if ($runningFamilies -contains [System.IO.Path]::GetFileName($package)) {
            $running = $true
            continue
        }
        foreach ($cache in $caches) { $targets.Add((Get-CleanTarget -Path $cache)) }
    }
    return (Get-CleanPlan -Targets ($targets.ToArray()) -Installed $true -Running $running)
}

function Get-SimpleDirectoryPlan {
    param($Spec, $Context)
    $cutoff = $script:NO_CUTOFF
    if ($Spec['UseAgeCutoff']) { $cutoff = $Context.AgeCutoff }
    $targets = New-Object -TypeName 'System.Collections.Generic.List[object]'
    foreach ($relative in $Spec['Paths']) {
        $directory = Join-BasePath -Base $Spec['Base'] -Relative $relative
        if (-not (Test-RealDirectory -Path $directory)) { continue }
        $targets.Add((Get-CleanTarget -Path $directory -Cutoff $cutoff -FilePatterns $Spec['FilePatterns']))
    }
    if ($targets.Count -eq 0) { return (Get-CleanPlan) }
    $processes = @($Spec['Processes'])
    if ($processes.Count -gt 0) {
        $isRunning = Test-AppRunning -Names $processes -CommandLinePattern $Spec['CommandLinePattern']
        if ($isRunning) { return (Get-CleanPlan -Installed $true -Running $true) }
    }
    return (Get-CleanPlan -Targets ($targets.ToArray()) -Installed $true)
}

function Get-DirectoryPlan {
    param([string]$Id, $Context)
    if ($Id -eq 'app-caches') { return (Get-AppCachePlan) }
    if ($Id -eq 'store-app-caches') { return (Get-StoreAppPlan) }
    foreach ($browser in $script:BROWSERS) {
        if ($browser['Id'] -eq $Id) { return (Get-BrowserPlan -Browser $browser) }
    }
    return (Get-SimpleDirectoryPlan -Spec $script:SIMPLE_DIRECTORY_CATEGORIES[$Id] -Context $Context)
}

# Returns the status a plan implies before any file is looked at, or $null when
# there are targets to measure or delete.
function Get-PlanEarlyState {
    param($Plan)
    if (@($Plan.Targets).Count -gt 0) { return $null }
    if ($Plan.Running) { return 'skipped_running' }
    if (-not $Plan.Installed) { return 'not_found' }
    return 'empty'
}

function Get-ScanMeasure {
    param([string]$Status, $Bytes = 0, $Files = 0, $Buckets = $null)
    return [pscustomobject]@{ Status = $Status; Bytes = $Bytes; Files = $Files; Buckets = $Buckets }
}

function Get-MeasuredState {
    param([int]$Files, [bool]$Denied)
    if ($Files -gt 0) { return 'ok' }
    if ($Denied) { return 'skipped_no_permission' }
    return 'empty'
}

# Splits plan targets by the delete guard so that scan and clean agree: a target the
# guard would refuse (a cache folder relocated through a link) is neither measured
# nor attempted.
function Get-GuardedTargetList {
    param([object[]]$Targets)
    $allowed = New-Object -TypeName 'System.Collections.Generic.List[object]'
    foreach ($target in $Targets) {
        if (Test-DeletionAllowed -Path $target.Path) { $allowed.Add($target) }
    }
    return [pscustomobject]@{ Targets = $allowed.ToArray() }
}

function Get-DirectoryScan {
    param([string]$Id, $Context)
    $plan = Get-DirectoryPlan -Id $Id -Context $Context
    $early = Get-PlanEarlyState -Plan $plan
    if ($null -ne $early) { return (Get-ScanMeasure -Status $early) }
    $guarded = Get-GuardedTargetList -Targets $plan.Targets
    if (@($guarded.Targets).Count -eq 0) { return (Get-ScanMeasure -Status 'unavailable') }
    $bytes = [long]0
    $files = 0
    $denied = $false
    foreach ($target in $guarded.Targets) {
        $measure = Measure-Target -Target $target
        $bytes += $measure.Bytes
        $files += $measure.Files
        if ($measure.Denied) { $denied = $true }
    }
    $status = Get-MeasuredState -Files $files -Denied $denied
    return (Get-ScanMeasure -Status $status -Bytes $bytes -Files $files)
}

function Get-CleanState {
    param([string]$Status, [long]$FreedBytes = 0, $ErrorCode = $null)
    $code = $ErrorCode
    if ($null -eq $code) { $code = $script:STATUS_ERROR_CODES[$Status] }
    return [pscustomobject]@{ Status = $Status; FreedBytes = $FreedBytes; ErrorCode = $code }
}

function Get-DeleteState {
    param([long]$FreedBytes, [int]$Deleted, [int]$Failed, [int]$Refused)
    if (($Failed -eq 0) -and ($Refused -eq 0)) {
        if ($Deleted -eq 0) { return (Get-CleanState -Status 'not_found') }
        return (Get-CleanState -Status 'cleaned' -FreedBytes $FreedBytes)
    }
    if ($Deleted -gt 0) { return (Get-CleanState -Status 'partial' -FreedBytes $FreedBytes) }
    if ($Failed -gt 0) { return (Get-CleanState -Status 'skipped_no_permission') }
    return (Get-CleanState -Status 'failed' -ErrorCode 'GUARD_REFUSED')
}

function Invoke-TargetListClean {
    param([object[]]$Targets, $Sink)
    $freed = [long]0
    $deleted = 0
    $failed = 0
    $refused = 0
    foreach ($target in $Targets) {
        $outcome = Invoke-GuardedDelete -Target $target -Sink $Sink
        $freed += $outcome.FreedBytes
        $deleted += $outcome.DeletedFiles
        $failed += $outcome.FailedCount
        if ($outcome.Refused) { $refused += 1 }
    }
    return (Get-DeleteState -FreedBytes $freed -Deleted $deleted -Failed $failed -Refused $refused)
}

function Invoke-DirectoryClean {
    param([string]$Id, $Context)
    $plan = Get-DirectoryPlan -Id $Id -Context $Context
    $early = Get-PlanEarlyState -Plan $plan
    if ($early -eq 'empty') { return (Get-CleanState -Status 'not_found') }
    if ($null -ne $early) { return (Get-CleanState -Status $early) }
    $guarded = Get-GuardedTargetList -Targets $plan.Targets
    if (@($guarded.Targets).Count -eq 0) {
        return (Get-CleanState -Status 'unavailable' -ErrorCode 'CUSTOM_LOCATION')
    }
    return (Invoke-TargetListClean -Targets $guarded.Targets -Sink $Context.Sink)
}

# Asks a tool for a directory. Answered is false when the tool fails or prints
# nothing; Path is $null when what it printed is not a usable absolute path.
function Get-ToolReportedPath {
    param([string]$Tool, [string[]]$Arguments)
    $reported = Invoke-Tool -Name $Tool -Arguments $Arguments
    $lines = @($reported.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (($reported.ExitCode -ne 0) -or ($lines.Count -eq 0)) {
        return [pscustomobject]@{ Answered = $false; Path = $null }
    }
    $last = ([string]$lines[$lines.Count - 1]).Trim()
    return [pscustomobject]@{ Answered = $true; Path = (Get-NormalizedPath -Path $last) }
}

function Get-ToolCacheState {
    param($Directory = $null, [bool]$Reported = $false, [bool]$Custom = $false)
    return [pscustomobject]@{ Directory = $Directory; Reported = $Reported; Custom = $Custom }
}

# Decides whether a tool's cache may be touched at all, for scan and clean alike. The
# tool is asked where its cache lives (it may have been pointed anywhere, even at a
# personal folder, by configuration or environment). Anything that is not at or below
# the catalog default and accepted by the delete guard is a custom location: the
# tool's clean command is then never run and nothing is deleted.
function Resolve-ToolCache {
    param($Spec)
    $default = Get-NormalizedPath -Path (Join-BasePath -Base $Spec['DefaultBase'] -Relative $Spec['DefaultPath'])
    if ($null -eq $default) { return (Get-ToolCacheState -Custom $true) }
    $answer = Get-ToolReportedPath -Tool $Spec['Tool'] -Arguments $Spec['DirArguments']
    $directory = $default
    if ($answer.Answered) { $directory = $answer.Path }
    if ($null -eq $directory) { return (Get-ToolCacheState -Custom $true) }
    $isDefault = $directory.Equals($default, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not ($isDefault -or (Test-PathInside -Child $directory -Parent $default))) {
        return (Get-ToolCacheState -Custom $true)
    }
    if ([System.IO.Directory]::Exists($directory) -and (-not (Test-DeletionAllowed -Path $directory))) {
        return (Get-ToolCacheState -Custom $true)
    }
    return (Get-ToolCacheState -Directory $directory -Reported $answer.Answered)
}

# The directory that is measured and, in the fallback case, deleted. $null when it
# does not exist as a real directory the delete guard accepts.
function Get-ToolCacheTarget {
    param($Spec, $Cache)
    $directory = [string]$Cache.Directory
    if (-not [string]::IsNullOrEmpty($Spec['SubPath'])) {
        $directory = [System.IO.Path]::Combine($directory, $Spec['SubPath'])
    }
    if (-not (Test-RealDirectory -Path $directory)) { return $null }
    if (-not (Test-DeletionAllowed -Path $directory)) { return $null }
    return (Get-CleanTarget -Path $directory)
}

function Get-ToolScan {
    param($Spec)
    if ($null -eq (Get-ToolPath -Name $Spec['Tool'])) { return (Get-ScanMeasure -Status 'not_found') }
    $cache = Resolve-ToolCache -Spec $Spec
    if ($cache.Custom) { return (Get-ScanMeasure -Status 'unavailable') }
    $status = 'empty'
    $bytes = [long]0
    $files = 0
    $target = Get-ToolCacheTarget -Spec $Spec -Cache $cache
    if ($null -ne $target) {
        $measure = Measure-Target -Target $target
        $status = Get-MeasuredState -Files $measure.Files -Denied $measure.Denied
        $bytes = $measure.Bytes
        $files = $measure.Files
    }
    $canClean = $cache.Reported -or $Spec['FallbackDelete']
    if (($status -eq 'ok') -and (-not $canClean)) { $status = 'unavailable' }
    if ($Spec['SizeUnknown']) { return (Get-ScanMeasure -Status $status -Bytes $null -Files $null) }
    return (Get-ScanMeasure -Status $status -Bytes $bytes -Files $files)
}

# The tool's own command runs only when the tool itself reported an accepted cache
# directory. When it could not report one, the default directory goes through the
# guarded delete instead (or the category is unavailable when that is not equivalent).
function Invoke-ToolClean {
    param($Spec, $Context)
    if ($null -eq (Get-ToolPath -Name $Spec['Tool'])) { return (Get-CleanState -Status 'not_found') }
    $cache = Resolve-ToolCache -Spec $Spec
    if ($cache.Custom) { return (Get-CleanState -Status 'unavailable' -ErrorCode 'CUSTOM_LOCATION') }
    $target = Get-ToolCacheTarget -Spec $Spec -Cache $cache
    if ($null -eq $target) { return (Get-CleanState -Status 'not_found') }
    $before = Measure-Target -Target $target
    $state = Get-MeasuredState -Files $before.Files -Denied $before.Denied
    if ($state -eq 'empty') { return (Get-CleanState -Status 'not_found') }
    if ($state -ne 'ok') { return (Get-CleanState -Status $state) }
    if (-not $cache.Reported) {
        if (-not $Spec['FallbackDelete']) { return (Get-CleanState -Status 'unavailable') }
        return (Invoke-TargetListClean -Targets @($target) -Sink $Context.Sink)
    }
    $run = Invoke-Tool -Name $Spec['Tool'] -Arguments $Spec['CleanArguments']
    if ($run.ExitCode -ne 0) { return (Get-CleanState -Status 'failed' -ErrorCode 'TOOL_FAILED') }
    $after = (Measure-Target -Target $target).Bytes
    $freed = [System.Math]::Max([long]0, ([long]$before.Bytes - [long]$after))
    return (Get-CleanState -Status 'cleaned' -FreedBytes $freed)
}

function Test-DockerReady {
    $info = Invoke-Tool -Name $script:DOCKER_TOOL -Arguments $script:DOCKER_INFO_ARGUMENTS
    return ($info.ExitCode -eq 0)
}

function Get-DockerScan {
    if ($null -eq (Get-ToolPath -Name $script:DOCKER_TOOL)) { return (Get-ScanMeasure -Status 'not_found') }
    if (-not (Test-DockerReady)) { return (Get-ScanMeasure -Status 'unavailable' -Bytes $null -Files $null) }
    $list = Invoke-Tool -Name $script:DOCKER_TOOL -Arguments $script:DOCKER_LIST_ARGUMENTS
    if ($list.ExitCode -ne 0) { return (Get-ScanMeasure -Status 'unavailable' -Bytes $null -Files $null) }
    $images = @($list.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($images.Count -eq 0) { return (Get-ScanMeasure -Status 'empty') }
    return (Get-ScanMeasure -Status 'ok' -Bytes $null -Files $images.Count)
}

function ConvertFrom-DockerReclaimed {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line -notmatch $script:DOCKER_RECLAIMED_PATTERN) { continue }
        $number = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $factor = $script:DOCKER_UNIT_FACTORS[$Matches[2].ToUpperInvariant()]
        return [long]($number * $factor)
    }
    return [long]0
}

function Invoke-DockerClean {
    if ($null -eq (Get-ToolPath -Name $script:DOCKER_TOOL)) { return (Get-CleanState -Status 'not_found') }
    if (-not (Test-DockerReady)) { return (Get-CleanState -Status 'unavailable') }
    $run = Invoke-Tool -Name $script:DOCKER_TOOL -Arguments $script:DOCKER_PRUNE_ARGUMENTS
    if ($run.ExitCode -ne 0) { return (Get-CleanState -Status 'failed' -ErrorCode 'TOOL_FAILED') }
    return (Get-CleanState -Status 'cleaned' -FreedBytes (ConvertFrom-DockerReclaimed -Lines $run.Output))
}

function Get-TrashScan {
    $info = Get-RecycleBinInfo
    if (-not $info.Available) { return (Get-ScanMeasure -Status 'unavailable') }
    if ($info.Items -eq 0) { return (Get-ScanMeasure -Status 'empty') }
    return (Get-ScanMeasure -Status 'ok' -Bytes $info.Bytes -Files $info.Items)
}

function Invoke-TrashClean {
    $info = Get-RecycleBinInfo
    if (-not $info.Available) { return (Get-CleanState -Status 'unavailable') }
    if ($info.Items -eq 0) { return (Get-CleanState -Status 'not_found') }
    if (-not (Invoke-RecycleBinEmpty)) { return (Get-CleanState -Status 'failed' -ErrorCode 'TOOL_FAILED') }
    return (Get-CleanState -Status 'cleaned' -FreedBytes $info.Bytes)
}
