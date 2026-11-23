# Installs the disk-cleanup Agent Skill into the skills directory of each AI agent on this machine.
# Usage: install.ps1 [-Agent NAME[,NAME...]] [-Uninstall] [-Local PATH] [-Help]
# The --agent / --uninstall / --local / --help spellings are accepted too.
# Arguments are parsed by hand so the script also works when piped to Invoke-Expression.

function Invoke-DiskCleanupInstaller {
    param([object[]]$Arguments)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $Version = 'v1.0.0'
    $Repo = 'awankkaley/disk-cleanup'
    $SkillName = 'disk-cleanup'
    $ArchiveUrl = "https://github.com/$Repo/archive/refs/tags/$Version.zip"
    $KnownAgents = @('claude', 'codex', 'cursor', 'gemini', 'copilot', 'opencode', 'amp', 'goose', 'agents')

    function Get-HomeDir {
        $homeDir = $env:USERPROFILE
        if ([string]::IsNullOrEmpty($homeDir)) { $homeDir = $HOME }
        if ([string]::IsNullOrEmpty($homeDir) -or -not (Test-Path -LiteralPath $homeDir -PathType Container)) {
            throw 'Could not find your user profile folder.'
        }
        return $homeDir
    }

    function Get-AgentMarkerDir {
        param([string]$Name, [string]$HomeDir)
        switch ($Name) {
            'claude' { return (Join-Path $HomeDir '.claude') }
            'codex' { return (Join-Path $HomeDir '.codex') }
            'cursor' { return (Join-Path $HomeDir '.cursor') }
            'gemini' { return (Join-Path $HomeDir '.gemini') }
            'copilot' { return (Join-Path $HomeDir '.copilot') }
            'opencode' { return (Join-Path (Join-Path $HomeDir '.config') 'opencode') }
            'amp' { return (Join-Path (Join-Path $HomeDir '.config') 'amp') }
            'goose' { return (Join-Path (Join-Path $HomeDir '.config') 'goose') }
            'agents' { return (Join-Path $HomeDir '.agents') }
        }
        throw "Unknown agent '$Name'."
    }

    # Codex, Amp and Goose read the shared .agents\skills directory.
    function Get-AgentSkillsDir {
        param([string]$Name, [string]$HomeDir)
        switch ($Name) {
            'claude' { return (Join-Path (Join-Path $HomeDir '.claude') 'skills') }
            'cursor' { return (Join-Path (Join-Path $HomeDir '.cursor') 'skills') }
            'gemini' { return (Join-Path (Join-Path $HomeDir '.gemini') 'skills') }
            'copilot' { return (Join-Path (Join-Path $HomeDir '.copilot') 'skills') }
            'opencode' { return (Join-Path (Join-Path (Join-Path $HomeDir '.config') 'opencode') 'skills') }
        }
        return (Join-Path (Join-Path $HomeDir '.agents') 'skills')
    }

    function Show-Usage {
        Write-Output "disk-cleanup skill installer ($Version)"
        Write-Output ''
        Write-Output 'Usage:'
        Write-Output '  install.ps1 [options]'
        Write-Output ''
        Write-Output 'Options:'
        Write-Output '  -Agent NAME    Install only for this agent. Repeatable, or a comma list.'
        Write-Output "                 Names: $($KnownAgents -join ' ')"
        Write-Output '  -Uninstall     Remove the skill instead of installing it.'
        Write-Output '  -Local PATH    Install from a local checkout instead of downloading.'
        Write-Output '  -Help          Show this help.'
        Write-Output ''
        Write-Output 'Without -Agent, the skill is installed for every agent found on this machine.'
        Write-Output "Only the `"$SkillName`" folder inside each agent's skills directory is written or removed."
    }

    function ConvertTo-AgentName {
        param([object]$Value)
        $names = @()
        foreach ($item in @($Value)) {
            foreach ($name in ([string]$item).Split(',')) {
                $trimmed = $name.Trim().ToLowerInvariant()
                if ($trimmed.Length -eq 0) { continue }
                if ($KnownAgents -notcontains $trimmed) {
                    throw "Unknown agent '$trimmed'. Known agents: $($KnownAgents -join ' ')"
                }
                $names += $trimmed
            }
        }
        if ($names.Count -eq 0) { throw "-Agent needs a name. Known agents: $($KnownAgents -join ' ')" }
        return $names
    }

    function Read-Options {
        param([object[]]$Items)
        $options = @{ Mode = 'install'; Local = ''; Agents = @(); Help = $false }
        $index = 0
        while ($index -lt $Items.Count) {
            $flag = ([string]$Items[$index]).TrimStart('-').ToLowerInvariant()
            $hasValue = ($index + 1) -lt $Items.Count
            switch ($flag) {
                'agent' {
                    if (-not $hasValue) { throw "-Agent needs a name. Known agents: $($KnownAgents -join ' ')" }
                    $options.Agents = @($options.Agents) + @(ConvertTo-AgentName -Value $Items[$index + 1])
                    $index += 2
                }
                'local' {
                    if (-not $hasValue) { throw '-Local needs a path to a checkout.' }
                    $options.Local = [string]$Items[$index + 1]
                    $index += 2
                }
                'uninstall' { $options.Mode = 'uninstall'; $index += 1 }
                'help' { $options.Help = $true; $index += 1 }
                default { throw "Unknown option '$($Items[$index])'. Run with -Help to see the options." }
            }
        }
        return $options
    }

    function Get-DetectedAgent {
        param([string]$HomeDir)
        $found = @()
        foreach ($name in $KnownAgents) {
            $marker = Get-AgentMarkerDir -Name $name -HomeDir $HomeDir
            if (Test-Path -LiteralPath $marker -PathType Container) { $found += $name }
        }
        return $found
    }

    function Get-TargetDir {
        param([string[]]$Agents, [string]$HomeDir)
        $dirs = @()
        foreach ($name in $Agents) {
            $dir = Get-AgentSkillsDir -Name $name -HomeDir $HomeDir
            if ($dirs -notcontains $dir) { $dirs += $dir }
        }
        return $dirs
    }

    function Assert-Source {
        param([string]$SourceDir)
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'SKILL.md') -PathType Leaf)) {
            throw "No SKILL.md found in the source. It does not look like a $SkillName checkout."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'scripts') -PathType Container)) {
            throw 'No scripts folder found in the source.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'LICENSE') -PathType Leaf)) {
            throw 'No LICENSE file found in the source.'
        }
    }

    function Get-DownloadedSource {
        param([string]$TempDir)
        Write-Output "Downloading $SkillName $Version ..." | Out-Host
        $zipPath = Join-Path $TempDir 'skill.zip'
        $extractDir = Join-Path $TempDir 'src'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zipPath -UseBasicParsing
        }
        catch {
            throw 'Download failed. Check your internet connection, or use -Local with a checkout.'
        }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
        $inner = @(Get-ChildItem -LiteralPath $extractDir -Directory)
        if ($inner.Count -ne 1) { throw 'The downloaded archive has an unexpected layout.' }
        return $inner[0].FullName
    }

    function Get-PathKey {
        param([string]$Path)
        return ([IO.Path]::GetFullPath($Path).TrimEnd('\') + '\')
    }

    # True when one folder is the other or lies inside it.
    function Test-PathOverlap {
        param([string]$First, [string]$Second)
        $firstKey = Get-PathKey -Path $First
        $secondKey = Get-PathKey -Path $Second
        if ($firstKey.StartsWith($secondKey, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        return $secondKey.StartsWith($firstKey, [StringComparison]::OrdinalIgnoreCase)
    }

    # An existing folder is only ever replaced or removed when it is this skill.
    function Test-OwnSkillDir {
        param([string]$Directory)
        $manifest = Join-Path $Directory 'SKILL.md'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $false }
        $pattern = '^name:\s*' + [regex]::Escape($SkillName) + '\s*$'
        foreach ($line in [IO.File]::ReadAllLines($manifest)) {
            if ($line -match $pattern) { return $true }
        }
        return $false
    }

    function Assert-Destination {
        param([string]$SkillsDir, [string]$SourceDir)
        $destination = Join-Path $SkillsDir $SkillName
        if ($SourceDir.Length -gt 0 -and (Test-PathOverlap -First $SourceDir -Second $destination)) {
            throw "The source folder overlaps the install location $destination. Use a checkout that is outside the agent's skills folder."
        }
        if (-not (Test-Path -LiteralPath $destination)) { return }
        if (-not (Test-OwnSkillDir -Directory $destination)) {
            throw "$destination already exists but is not this skill (it has no SKILL.md with 'name: $SkillName'). Nothing was changed. Move or delete that folder yourself, then run again."
        }
    }

    function Remove-SkillDir {
        param([string]$Destination)
        $item = Get-Item -LiteralPath $Destination -Force
        $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isLink) {
            # Delete() on a link removes the link itself and never its target.
            $item.Delete()
        }
        else {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
    }

    function Install-Into {
        param([string]$SkillsDir, [string]$SourceDir)
        $destination = Join-Path $SkillsDir $SkillName
        if (-not (Test-Path -LiteralPath $SkillsDir)) {
            New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
        }
        if (Test-Path -LiteralPath $destination) { Remove-SkillDir -Destination $destination }
        New-Item -ItemType Directory -Path $destination | Out-Null
        Copy-Item -LiteralPath (Join-Path $SourceDir 'SKILL.md') -Destination $destination
        Copy-Item -LiteralPath (Join-Path $SourceDir 'LICENSE') -Destination $destination
        Copy-Item -LiteralPath (Join-Path $SourceDir 'scripts') -Destination $destination -Recurse
        Write-Output "  installed  $destination" | Out-Host
    }

    function Uninstall-From {
        param([string]$SkillsDir)
        $destination = Join-Path $SkillsDir $SkillName
        if (Test-Path -LiteralPath $destination) {
            Remove-SkillDir -Destination $destination
            Write-Output "  removed    $destination" | Out-Host
        }
    }

    function Invoke-Install {
        param([hashtable]$Options, [string]$HomeDir)
        $agents = @($Options.Agents)
        if ($agents.Count -eq 0) { $agents = @(Get-DetectedAgent -HomeDir $HomeDir) }
        if ($agents.Count -eq 0) {
            throw "No supported AI agent found on this machine. Pick one with -Agent (names: $($KnownAgents -join ' '))."
        }
        $tempDir = $null
        try {
            if ($Options.Local.Length -gt 0) {
                if (-not (Test-Path -LiteralPath $Options.Local -PathType Container)) {
                    throw '-Local path is not a folder.'
                }
                $sourceDir = (Resolve-Path -LiteralPath $Options.Local).ProviderPath
            }
            else {
                $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("$SkillName-install-" + [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $tempDir | Out-Null
                $sourceDir = Get-DownloadedSource -TempDir $tempDir
            }
            Assert-Source -SourceDir $sourceDir
            $targetDirs = @(Get-TargetDir -Agents $agents -HomeDir $HomeDir)
            foreach ($dir in $targetDirs) { Assert-Destination -SkillsDir $dir -SourceDir $sourceDir }
            Write-Output "Installing $SkillName for: $($agents -join ' ')" | Out-Host
            foreach ($dir in $targetDirs) {
                Install-Into -SkillsDir $dir -SourceDir $sourceDir
            }
        }
        finally {
            if ($null -ne $tempDir -and (Test-Path -LiteralPath $tempDir)) {
                Remove-Item -LiteralPath $tempDir -Recurse -Force
            }
        }
        Write-Output 'Done. Restart your AI agent, then ask it something like: "My disk is almost full, help me free up space."' | Out-Host
    }

    function Invoke-Uninstall {
        param([hashtable]$Options, [string]$HomeDir)
        $agents = @($Options.Agents)
        if ($agents.Count -eq 0) { $agents = $KnownAgents }
        $targetDirs = @(Get-TargetDir -Agents $agents -HomeDir $HomeDir)
        foreach ($dir in $targetDirs) { Assert-Destination -SkillsDir $dir -SourceDir '' }
        Write-Output "Removing $SkillName ..." | Out-Host
        foreach ($dir in $targetDirs) {
            Uninstall-From -SkillsDir $dir
        }
        Write-Output 'Done.' | Out-Host
    }

    try {
        $options = Read-Options -Items @($Arguments)
        if ($options.Help) {
            Show-Usage | Out-Host
            return 0
        }
        $homeDir = Get-HomeDir
        if ($options.Mode -eq 'uninstall') {
            Invoke-Uninstall -Options $options -HomeDir $homeDir
        }
        else {
            Invoke-Install -Options $options -HomeDir $homeDir
        }
        return 0
    }
    catch {
        Write-Output "Error: $($_.Exception.Message)" | Out-Host
        return 1
    }
}

$installerExitCode = Invoke-DiskCleanupInstaller -Arguments @($args)
if ($PSCommandPath) {
    exit $installerExitCode
}
# Piped to Invoke-Expression: "exit" would close the user's window, so raise an error instead.
if ($installerExitCode -ne 0) {
    throw 'disk-cleanup installation failed.'
}
