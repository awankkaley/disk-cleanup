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

# Ends the one child process this script started itself, and only after it ran past
# the timeout. No other process is ever terminated.
function Stop-ToolChild {
    param($Process)
    try {
        $Process.Kill()
    } catch {
        # The child exited on its own in the meantime; the caller reports the timeout either way.
        return
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
