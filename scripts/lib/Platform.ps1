$script:RECYCLE_BIN_NAMESPACE = 10
$script:RECYCLE_BIN_SIZE_PROPERTY = 'System.Size'
$script:TOOL_FAILURE_EXIT_CODE = -1
$script:TOOL_TIMEOUT_MILLISECONDS = 120000
$script:TOOL_OUTPUT_GRACE_MILLISECONDS = 5000
$script:TOOL_EXTENSIONS = @('.exe', '.com', '.cmd', '.bat')
$script:BATCH_EXTENSIONS = @('.cmd', '.bat')
$script:COMMAND_SHELL_NAME = 'cmd.exe'
$script:ARGUMENT_NEEDS_QUOTES_PATTERN = '[\s"]'
$script:LINE_BREAK_PATTERN = '\r?\n'
$script:NT_PATH_PREFIX = '\??\'
$script:STORE_PROCESS_PATH_PATTERN = '\\WindowsApps\\([^\\_]+)_[^\\]*_([^\\_]+)\\'

# Together with Get-RunningPackageFamilyList, the only place that asks Windows which
# apps are open. With a command line pattern, a process counts only when its command
# line matches (Gradle daemon).
function Test-AppRunning {
    param([string[]]$Names, [string]$CommandLinePattern = '')
    foreach ($name in $Names) {
        if ([string]::IsNullOrEmpty($CommandLinePattern)) {
            $found = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) { return $true }
            continue
        }
        $filter = "Name = '$name.exe'"
        $candidates = @(Get-CimInstance -ClassName Win32_Process -Filter $filter -ErrorAction SilentlyContinue)
        foreach ($candidate in $candidates) {
            if (([string]$candidate.CommandLine) -like $CommandLinePattern) { return $true }
        }
    }
    return $false
}

# Package family names (the folder names below Packages) of Store apps that have a
# process open. A process whose image path cannot be read is not reported.
function Get-RunningPackageFamilyList {
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $imagePath = [string]$process.Path
        } catch {
            continue
        }
        if ($imagePath -match $script:STORE_PROCESS_PATH_PATTERN) { $Matches[1] + '_' + $Matches[2] }
    }
}

# The profile directory Windows records for the account, independent of the
# USERPROFILE variable. $null when it cannot be determined.
function Get-AccountProfilePath {
    try {
        $path = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    } catch {
        return $null
    }
    if ([string]::IsNullOrEmpty($path)) { return $null }
    return $path
}

# Where a junction or directory symlink points, normalized. Returns nothing when the
# target cannot be read.
function Get-LinkTargetPath {
    param([System.IO.FileSystemInfo]$Link)
    try {
        $targets = @($Link.Target | Where-Object { -not [string]::IsNullOrEmpty($_) })
    } catch {
        return
    }
    if ($targets.Count -eq 0) { return }
    $target = [string]$targets[0]
    if ($target.StartsWith($script:NT_PATH_PREFIX)) { $target = $target.Substring($script:NT_PATH_PREFIX.Length) }
    if ($target -notmatch $script:ABSOLUTE_PATH_PATTERN) {
        $target = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Link.FullName), $target)
    }
    return (Get-NormalizedPath -Path $target)
}

function Get-DiskInfo {
    try {
        $root = [System.IO.Path]::GetPathRoot($env:USERPROFILE)
        $drive = New-Object -TypeName System.IO.DriveInfo -ArgumentList $root
        $total = [long]$drive.TotalSize
        $free = [long]$drive.AvailableFreeSpace
    } catch {
        return [pscustomobject]@{ TotalBytes = $null; FreeBytes = $null }
    }
    return [pscustomobject]@{ TotalBytes = $total; FreeBytes = $free }
}

function Get-RecycleBinItemSize {
    param($Item)
    $size = $Item.ExtendedProperty($script:RECYCLE_BIN_SIZE_PROPERTY)
    if ($null -eq $size) { $size = $Item.Size }
    if ($null -eq $size) { return [long]0 }
    return [long]$size
}

function Get-RecycleBinInfo {
    $bytes = [long]0
    $count = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace($script:RECYCLE_BIN_NAMESPACE)
        foreach ($item in $folder.Items()) {
            $bytes += Get-RecycleBinItemSize -Item $item
            $count += 1
        }
    } catch {
        return [pscustomobject]@{ Available = $false; Bytes = [long]0; Items = 0 }
    }
    return [pscustomobject]@{ Available = $true; Bytes = $bytes; Items = $count }
}

function Invoke-RecycleBinEmpty {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
    } catch {
        return $false
    }
    return $true
}

# Only real executables and batch shims found on PATH count; the current directory
# is never searched, so a project-local shim cannot stand in for a tool.
function Get-ToolPath {
    param([string]$Name)
    $commands = @(Get-Command -Name $Name -CommandType Application -All -ErrorAction SilentlyContinue)
    foreach ($command in $commands) {
        $extension = [System.IO.Path]::GetExtension([string]$command.Path).ToLowerInvariant()
        if ($script:TOOL_EXTENSIONS -contains $extension) { return [string]$command.Path }
    }
    return $null
}

function Get-ToolTimeoutMillisecond {
    return $script:TOOL_TIMEOUT_MILLISECONDS
}

function Get-ToolFailure {
    return [pscustomobject]@{ ExitCode = $script:TOOL_FAILURE_EXIT_CODE; Output = @() }
}

function ConvertTo-ToolArgument {
    param([string]$Value)
    if ($Value -notmatch $script:ARGUMENT_NEEDS_QUOTES_PATTERN) { return $Value }
    return ('"' + $Value.Replace('"', '\"') + '"')
}

# Batch shims (npm.cmd, yarn.cmd, pnpm.cmd) cannot be started directly without a
# shell, so they go through cmd.exe from the system directory.
function Get-ToolStartInfo {
    param([string]$Path, [string[]]$Arguments, [string]$WorkingDirectory)
    $line = (@($Arguments | ForEach-Object { ConvertTo-ToolArgument -Value $_ }) -join ' ')
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $Path
    $info.Arguments = $line
    if ($script:BATCH_EXTENSIONS -contains [System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        $info.FileName = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, $script:COMMAND_SHELL_NAME)
        $info.Arguments = '/d /s /c ""' + $Path + '" ' + $line + '"'
    }
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    return $info
}

# Ids of the child this script started plus the processes that child spawned after
# it started (a batch shim runs the real tool as a grandchild). The start-time check
# keeps a recycled process id from ever pointing at an unrelated process.
function Get-ToolChildTreeIdList {
    param($Process)
    $ids = New-Object -TypeName 'System.Collections.Generic.List[int]'
    $ids.Add([int]$Process.Id)
    try {
        $startTime = $Process.StartTime
        $all = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
    } catch {
        return $ids.ToArray()
    }
    $index = 0
    while ($index -lt $ids.Count) {
        $parentId = $ids[$index]
        foreach ($item in $all) {
            if ([int]$item.ParentProcessId -ne $parentId) { continue }
            if ($null -eq $item.CreationDate -or $item.CreationDate -lt $startTime) { continue }
            if (-not $ids.Contains([int]$item.ProcessId)) { $ids.Add([int]$item.ProcessId) }
        }
        $index++
    }
    return $ids.ToArray()
}

# Ends the one child process tree this script started itself, and only after it ran
# past the timeout. No other process is ever terminated.
function Stop-ToolChild {
    param($Process)
    $ids = @(Get-ToolChildTreeIdList -Process $Process)
    [array]::Reverse($ids)
    foreach ($id in $ids) {
        try {
            [System.Diagnostics.Process]::GetProcessById($id).Kill()
        } catch {
            # Already exited on its own; the caller reports the timeout either way.
            continue
        }
    }
}

# Starts the tool with stdin closed, drains and discards stderr, and gives up after
# the timeout. Output is read asynchronously so a full pipe cannot block the child.
function Invoke-ToolProcess {
    param($StartInfo)
    $process = New-Object -TypeName System.Diagnostics.Process
    $process.StartInfo = $StartInfo
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit((Get-ToolTimeoutMillisecond))) {
            Stop-ToolChild -Process $process
            [void]$process.WaitForExit($script:TOOL_OUTPUT_GRACE_MILLISECONDS)
            return (Get-ToolFailure)
        }
        $exitCode = $process.ExitCode
        if (-not $outputTask.Wait($script:TOOL_OUTPUT_GRACE_MILLISECONDS)) { return (Get-ToolFailure) }
        $text = [string]$outputTask.Result
    } catch {
        return (Get-ToolFailure)
    } finally {
        $process.Dispose()
    }
    $lines = [string[]]@($text -split $script:LINE_BREAK_PATTERN)
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $lines }
}

# Runs an external tool and returns its exit code plus stdout lines. The working
# directory is the state directory, never the caller's: the caller usually sits in
# a project, where npm and yarn would pick up project-local configuration.
function Invoke-Tool {
    param([string]$Name, [string[]]$Arguments)
    $path = Get-ToolPath -Name $Name
    if ($null -eq $path) { return (Get-ToolFailure) }
    try {
        $workingDirectory = Get-StateDirectory
        if (Test-PathIsLinkIfPresent -Path $workingDirectory) { return (Get-ToolFailure) }
        [void][System.IO.Directory]::CreateDirectory($workingDirectory)
        $startInfo = Get-ToolStartInfo -Path $path -Arguments $Arguments -WorkingDirectory $workingDirectory
    } catch {
        return (Get-ToolFailure)
    }
    return (Invoke-ToolProcess -StartInfo $startInfo)
}

$script:SKIP_SEAM_VALUE = '1'
$script:RECYCLE_TRASHED = 'trashed'
$script:RECYCLE_DENIED = 'denied'
$script:RECYCLE_FAILED = 'failed'
$script:RECYCLE_POLICY_KEY = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$script:RECYCLE_POLICY_VALUE = 'NoRecycleFiles'
$script:RECYCLE_VOLUME_KEY = 'Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume'
$script:RECYCLE_CAPACITY_VALUE = 'MaxCapacity'
$script:RECYCLE_BYPASS_VALUE = 'NukeOnDelete'
$script:RECYCLE_CAPACITY_UNIT_BYTES = 1048576
$script:RECYCLE_FALLBACK_DIVISOR = 20
$script:REGISTRY_SWITCH_ON = 1
$script:VOLUME_GUID_PATTERN = '\{[0-9A-Fa-f-]{36}\}'
$script:DRIVE_NAME_LENGTH = 2
$script:NATIVE_NAMESPACE = 'DiskCleanupNative'
$script:NATIVE_TYPE_NAME = 'FileSize'
$script:NATIVE_SIZE_MEMBER = @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
private static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);

public static long Measure(string path)
{
    uint high;
    uint low = GetCompressedFileSizeW(path, out high);
    if (low == 0xFFFFFFFF && Marshal.GetLastWin32Error() != 0) { return -1; }
    return ((long)high << 32) + (long)low;
}
'@

# The only place that opens anything for the user: the local review report, handed to
# the shell so the default browser shows it. No verb is set, so nothing is elevated.
# The environment switch can only suppress the open; tests and unattended runs use it.
function Open-ReviewReport {
    param([string]$Path)
    if ($env:DISK_CLEANUP_SKIP_REPORT_OPEN -eq $script:SKIP_SEAM_VALUE) { return $false }
    try {
        $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $info.FileName = $Path
        $info.UseShellExecute = $true
        $process = [System.Diagnostics.Process]::Start($info)
        if ($null -ne $process) { $process.Dispose() }
    } catch {
        return $false
    }
    return $true
}

function Test-AccessDeniedError {
    param($Exception)
    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [System.UnauthorizedAccessException]) { return $true }
        if ($current -is [System.Security.SecurityException]) { return $true }
        $current = $current.InnerException
    }
    return $false
}

# The only place that moves a personal file, and it only ever moves it to the Recycle
# Bin, where the user can restore it. Nothing here deletes permanently. The
# environment switch can only make it do nothing and report a failure.
function Send-FileToRecycleBin {
    param([string]$Path)
    if ($env:DISK_CLEANUP_SKIP_RECYCLE -eq $script:SKIP_SEAM_VALUE) { return $script:RECYCLE_FAILED }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } catch {
        if (Test-AccessDeniedError -Exception $_.Exception) { return $script:RECYCLE_DENIED }
        return $script:RECYCLE_FAILED
    }
    return $script:RECYCLE_TRASHED
}

function Get-RegistryNumber {
    param($Hive, [string]$KeyPath, [string]$Name)
    $key = $Hive.OpenSubKey($KeyPath)
    if ($null -eq $key) { return $null }
    try {
        $value = $key.GetValue($Name)
    } finally {
        $key.Dispose()
    }
    if ($null -eq $value) { return $null }
    return [long]$value
}

function Test-RecyclePolicyOff {
    foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser, [Microsoft.Win32.Registry]::LocalMachine)) {
        $setting = Get-RegistryNumber -Hive $hive -KeyPath $script:RECYCLE_POLICY_KEY -Name $script:RECYCLE_POLICY_VALUE
        if ($setting -eq $script:REGISTRY_SWITCH_ON) { return $true }
    }
    return $false
}

# Registry keys that hold the Recycle Bin settings to respect for a file: the key of
# the file's own volume when Windows can name that volume, otherwise every volume key
# of the user, so that the strictest setting applies.
function Get-RecycleVolumeKeyList {
    param([string]$Path)
    $drive = [System.IO.Path]::GetPathRoot($Path).Substring(0, $script:DRIVE_NAME_LENGTH)
    $filter = "DriveLetter = '" + $drive + "'"
    try {
        $volumes = @(Get-CimInstance -ClassName Win32_Volume -Filter $filter -ErrorAction Stop)
    } catch {
        $volumes = @()
    }
    if ($volumes.Count -eq 1) {
        $found = [regex]::Match([string]$volumes[0].DeviceID, $script:VOLUME_GUID_PATTERN)
        if ($found.Success) { return ($script:RECYCLE_VOLUME_KEY + '\' + $found.Value) }
    }
    $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:RECYCLE_VOLUME_KEY)
    if ($null -eq $root) { return }
    try {
        $names = @($root.GetSubKeyNames())
    } finally {
        $root.Dispose()
    }
    foreach ($name in $names) { $script:RECYCLE_VOLUME_KEY + '\' + $name }
}

# Largest file, in bytes, the Recycle Bin accepts for this file: 0 when the user
# turned the bin off, $null when Windows has no setting to go by.
function Get-RecycleVolumeLimit {
    param([string]$Path)
    $user = [Microsoft.Win32.Registry]::CurrentUser
    $limit = $null
    foreach ($keyPath in @(Get-RecycleVolumeKeyList -Path $Path)) {
        $bypass = Get-RegistryNumber -Hive $user -KeyPath $keyPath -Name $script:RECYCLE_BYPASS_VALUE
        if ($bypass -eq $script:REGISTRY_SWITCH_ON) { return [long]0 }
        $capacity = Get-RegistryNumber -Hive $user -KeyPath $keyPath -Name $script:RECYCLE_CAPACITY_VALUE
        if ($null -eq $capacity) { continue }
        $bytes = [long]$capacity * $script:RECYCLE_CAPACITY_UNIT_BYTES
        if (($null -eq $limit) -or ($bytes -lt $limit)) { $limit = $bytes }
    }
    return $limit
}

# Windows silently destroys a file that is too big for the Recycle Bin, or any file
# when the bin is switched off, instead of recycling it. Such a file is never handed
# over. Without a per-volume setting the smallest Windows default (5% of the volume)
# is assumed. Any doubt counts as "does not fit".
function Test-RecycleBinCanHold {
    param([string]$Path, [long]$Bytes)
    try {
        if (Test-RecyclePolicyOff) { return $false }
        $limit = Get-RecycleVolumeLimit -Path $Path
        if ($null -eq $limit) {
            $drive = New-Object -TypeName System.IO.DriveInfo -ArgumentList ([System.IO.Path]::GetPathRoot($Path))
            $limit = [long][System.Math]::Floor([double]$drive.TotalSize / $script:RECYCLE_FALLBACK_DIVISOR)
        }
    } catch {
        return $false
    }
    return ($Bytes -le $limit)
}

# Bytes the file really occupies on disk (smaller than its length for sparse,
# compressed and cloud-only files). $null when Windows cannot say.
function Get-AllocatedFileSize {
    param([string]$Path)
    try {
        $typeName = $script:NATIVE_NAMESPACE + '.' + $script:NATIVE_TYPE_NAME
        if ($null -eq ($typeName -as [type])) {
            Add-Type -MemberDefinition $script:NATIVE_SIZE_MEMBER -Name $script:NATIVE_TYPE_NAME `
                -Namespace $script:NATIVE_NAMESPACE
        }
        $native = $typeName -as [type]
        $size = [long]$native::Measure($Path)
        if ($size -lt 0) { return $null }
        return $size
    } catch {
        return $null
    }
}
