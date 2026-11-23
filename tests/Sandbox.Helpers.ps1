# Shared fixtures for the Pester suites. Every fixture name carries the marker
# 'zq' so the privacy assertions can prove that no fixture name reaches stdout.

$script:FIXTURE_MARKER = 'zq'
$script:SANDBOX_ENV_NAMES = @('USERPROFILE', 'LOCALAPPDATA', 'APPDATA')
$script:SavedEnvironment = @{}
$script:SandboxJunctions = New-Object -TypeName 'System.Collections.Generic.List[string]'

function Initialize-Sandbox {
    param([string]$Root)
    $base = Join-Path -Path $Root -ChildPath ('zqsandbox' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $homeDir = Join-Path -Path $base -ChildPath 'users\zqfixtureuser'
    $sandbox = [pscustomobject]@{
        Base      = $base
        Home      = $homeDir
        Local     = Join-Path -Path $homeDir -ChildPath 'AppData\Local'
        Roaming   = Join-Path -Path $homeDir -ChildPath 'AppData\Roaming'
        Temp      = Join-Path -Path $homeDir -ChildPath 'AppData\Local\Temp'
        Outside   = Join-Path -Path $base -ChildPath 'zqoutside'
        StateDir  = Join-Path -Path $homeDir -ChildPath 'AppData\Local\disk-cleanup'
        StateFile = Join-Path -Path $homeDir -ChildPath 'AppData\Local\disk-cleanup\state'
    }
    foreach ($directory in @($sandbox.Local, $sandbox.Roaming, $sandbox.Temp, $sandbox.Outside)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    foreach ($name in $script:SANDBOX_ENV_NAMES) {
        if ($script:SavedEnvironment.ContainsKey($name)) { continue }
        $script:SavedEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name)
    }
    $env:USERPROFILE = $sandbox.Home
    $env:LOCALAPPDATA = $sandbox.Local
    $env:APPDATA = $sandbox.Roaming
    return $sandbox
}

function Restore-SandboxEnvironment {
    foreach ($link in @($script:SandboxJunctions.ToArray())) {
        if ([System.IO.Directory]::Exists($link)) { [System.IO.Directory]::Delete($link, $false) }
    }
    $script:SandboxJunctions.Clear()
    foreach ($name in $script:SANDBOX_ENV_NAMES) {
        if ($script:SavedEnvironment.ContainsKey($name)) {
            [System.Environment]::SetEnvironmentVariable($name, $script:SavedEnvironment[$name])
        }
    }
}

function Add-SandboxFile {
    param([string]$Path, [int]$AgeDays = 0, [int]$SizeBytes = 16)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    [System.IO.File]::WriteAllBytes($Path, (New-Object -TypeName byte[] -ArgumentList $SizeBytes))
    if ($AgeDays -gt 0) {
        [System.IO.File]::SetLastWriteTimeUtc($Path, [System.DateTime]::UtcNow.AddDays(-1 * $AgeDays))
    }
}

function Add-SandboxJunction {
    param([string]$Link, [string]$Target)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Link))
    New-Item -ItemType Junction -Path $Link -Value $Target | Out-Null
    $script:SandboxJunctions.Add($Link)
}

function Add-SandboxProject {
    param(
        [string]$Directory,
        [int]$IdleDays,
        [string]$Lockfile = 'package-lock.json',
        [bool]$WithManifest = $true,
        [int]$ModuleBytes = 100
    )
    if ($WithManifest) { Add-SandboxFile -Path (Join-Path -Path $Directory -ChildPath 'package.json') -AgeDays $IdleDays }
    if ($Lockfile.Length -gt 0) { Add-SandboxFile -Path (Join-Path -Path $Directory -ChildPath $Lockfile) -AgeDays $IdleDays }
    Add-SandboxFile -Path (Join-Path -Path $Directory -ChildPath 'src\zqsource.js') -AgeDays $IdleDays
    $modulePath = Join-Path -Path $Directory -ChildPath 'node_modules\zqpackage\index.js'
    Add-SandboxFile -Path $modulePath -AgeDays $IdleDays -SizeBytes $ModuleBytes
}

function Get-SandboxFileList {
    param([string]$Root)
    $files = [System.IO.Directory]::GetFiles($Root, '*', [System.IO.SearchOption]::AllDirectories)
    return @($files | Sort-Object)
}

function Invoke-CleanupJson {
    param([string[]]$Arguments)
    $outcome = Invoke-Cleanup -Arguments $Arguments
    return [pscustomobject]@{
        ExitCode = $outcome.ExitCode
        Json     = $outcome.Json
        Data     = (ConvertFrom-Json -InputObject $outcome.Json)
    }
}

function Get-CategoryEntry {
    param($Data, [string]$Id)
    return @($Data.categories | Where-Object { $_.id -eq $Id })[0]
}

function Get-ResultEntry {
    param($Data, [string]$Id)
    return @($Data.results | Where-Object { $_.id -eq $Id })[0]
}

function Set-SandboxStateEpoch {
    param([string]$StateFile, [string]$Replacement)
    $text = [System.IO.File]::ReadAllText($StateFile)
    $changed = [regex]::Replace($text, '"epoch":[0-9]+', ('"epoch":' + $Replacement))
    [System.IO.File]::WriteAllText($StateFile, $changed)
}

function Get-EpochNow {
    $origin = New-Object -TypeName System.DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
    return [long][System.Math]::Floor(([System.DateTime]::UtcNow - $origin).TotalSeconds)
}

function Get-JsonStringList {
    param($Node)
    if ($null -eq $Node) { return }
    if ($Node -is [string]) {
        $Node
        return
    }
    if ($Node -is [System.Array]) {
        foreach ($item in $Node) { Get-JsonStringList -Node $item }
        return
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Node.PSObject.Properties) {
            $property.Name
            if ($property.Name -ne 'log_location_hint') { Get-JsonStringList -Node $property.Value }
        }
    }
}

# Asserts the privacy contract on one stdout document: no path separators in any
# string, no sandbox path, no fixture name, no real or fixture user name.
function Assert-PrivateOutput {
    param([string]$Json, $Sandbox)
    $data = ConvertFrom-Json -InputObject $Json
    foreach ($text in @(Get-JsonStringList -Node $data)) {
        $text | Should -Not -Match '[\\/]'
        $text | Should -Not -Match '^[A-Za-z]:'
    }
    $Json | Should -Not -Match $script:FIXTURE_MARKER
    $Json | Should -Not -Match ([regex]::Escape((Split-Path -Path $Sandbox.Base -Leaf)))
    $Json | Should -Not -MatchExactly 'AppData'
    $realUser = [string]$env:USERNAME
    if ($realUser.Length -gt 2) { $Json | Should -Not -Match ([regex]::Escape($realUser)) }
}

function Add-SandboxFileSet {
    param([string]$Root, [object[]]$Rows)
    foreach ($row in $Rows) {
        $age = 0
        if ($row.Count -gt 2) { $age = [int]$row[2] }
        Add-SandboxFile -Path (Join-Path -Path $Root -ChildPath ([string]$row[0])) -SizeBytes ([int]$row[1]) -AgeDays $age
    }
}

# Cleanable fixtures. Expected scan totals with the default 7 day age threshold:
# browser-chrome 200/4, temp-files 100/2, crash-dumps 70/1, thumbnail-cache 50/2,
# store-app-caches 25/2, app-caches 43/2, gradle-cache 33/1, cargo-cache 69/2 = 590.
function Add-SandboxCache {
    param($Sandbox)
    Add-SandboxFileSet -Root $Sandbox.Local -Rows @(
        @('Google\Chrome\User Data\Default\Cache\Cache_Data\zqblob1', 100),
        @('Google\Chrome\User Data\Default\Code Cache\js\zqblob2', 50),
        @('Google\Chrome\User Data\Default\GPUCache\zqblob3', 25),
        @('Google\Chrome\User Data\Profile 1\Cache\zqblob4', 25),
        @('Temp\zqold.tmp', 40, 30),
        @('Temp\zqdir\zqolder.tmp', 60, 60),
        @('Temp\zqfresh.tmp', 10),
        @('CrashDumps\zqold.dmp', 70, 30),
        @('CrashDumps\zqnew.dmp', 5),
        @('Microsoft\Windows\Explorer\thumbcache_256.db', 30),
        @('Microsoft\Windows\Explorer\iconcache_48.db', 20),
        @('Packages\zqPackage_abc\TempState\zqtemp.bin', 12),
        @('Packages\zqPackage_abc\AC\INetCache\zqnet.bin', 13)
    )
    Add-SandboxFileSet -Root $Sandbox.Roaming -Rows @(
        @('Slack\Cache\zqslack.bin', 21),
        @('Code\CachedData\zqcode.bin', 22)
    )
    Add-SandboxFileSet -Root $Sandbox.Home -Rows @(
        @('.gradle\caches\zqmodules\zqjar.bin', 33),
        @('.cargo\registry\cache\zqindex\zqcrate.bin', 34),
        @('.cargo\registry\src\zqindex\zqsrc.rs', 35)
    )
}

# Files that no scan or clean may ever remove. Returns their full paths.
function Add-SandboxSentinel {
    param($Sandbox)
    $relative = @(
        'Documents\zqreport.docx', 'Desktop\zqnote.txt', 'Downloads\zqinstaller.exe', 'Pictures\zqphoto.jpg',
        'Music\zqsong.mp3', 'Videos\zqclip.mp4', 'OneDrive\zqcloud.txt',
        'AppData\Local\Google\Chrome\User Data\Local State',
        'AppData\Local\Google\Chrome\User Data\Default\Cookies',
        'AppData\Local\Google\Chrome\User Data\Default\History',
        'AppData\Local\Google\Chrome\User Data\Default\Login Data',
        'AppData\Local\Google\Chrome\User Data\Default\Bookmarks',
        'AppData\Local\Google\Chrome\User Data\Default\Sessions\zqsession',
        'AppData\Local\Google\Chrome\User Data\Default\Extensions\zqext\manifest.json',
        'AppData\Local\Google\Chrome\User Data\Default\Service Worker\CacheStorage\zqworker',
        'AppData\Local\Google\Chrome\User Data\zqNotAProfile\Cache\zqkept',
        'AppData\Local\Microsoft\Windows\Explorer\zqother.db',
        'AppData\Local\Packages\zqPackage_abc\LocalCache\zqcache.bin',
        'AppData\Local\Packages\zqPackage_abc\LocalCache\Local\zqdata.db',
        'AppData\Local\Packages\zqPackage_abc\LocalCache\Roaming\zqsettings.json',
        'AppData\Local\Packages\zqPackage_abc\LocalState\zqstate.db',
        'AppData\Local\Packages\zqPackage_abc\Settings\settings.dat',
        'AppData\Roaming\Slack\storage\zqdata.json',
        'AppData\Roaming\Code\User\settings.json',
        'AppData\Roaming\zqUnknownApp\Cache\zqkept.bin',
        '.gradle\gradle.properties',
        '.cargo\bin\zqtool.exe',
        '.cargo\registry\index\zqindex\zqentry'
    )
    $paths = @(foreach ($item in $relative) { Join-Path -Path $Sandbox.Home -ChildPath $item })
    $paths += (Join-Path -Path $Sandbox.Outside -ChildPath 'zqkeep.txt')
    foreach ($path in $paths) { Add-SandboxFile -Path $path -AgeDays 400 }
    return $paths
}

# Replaces a real folder with a junction to a copy outside the user profile, the
# way a relocated tool cache looks on disk.
function Move-SandboxFolderBehindJunction {
    param([string]$Folder, [string]$NewLocation)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($NewLocation))
    [System.IO.Directory]::Move($Folder, $NewLocation)
    Add-SandboxJunction -Link $Folder -Target $NewLocation
}

# Writes a batch file that stands in for an external tool.
function Add-SandboxBatchTool {
    param([string]$Path, [string[]]$Lines)
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $encoding = New-Object -TypeName System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), $encoding)
}

function Test-WindowsHost {
    return ($env:OS -eq 'Windows_NT')
}

# A writable folder that is not inside the real profile of the account running the
# tests, for child-process runs where the profile trust check cannot be mocked.
# Returns $null when no such folder exists.
function Get-ExternalSandboxRoot {
    $realProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    foreach ($candidate in @($env:RUNNER_TEMP, $env:PUBLIC, $env:ProgramData)) {
        if ([string]::IsNullOrEmpty($candidate)) { continue }
        if (-not [System.IO.Directory]::Exists($candidate)) { continue }
        $full = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\') + '\'
        $inside = (-not [string]::IsNullOrEmpty($realProfile)) -and
            $full.StartsWith(($realProfile.TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $inside) { return $candidate }
    }
    return $null
}
