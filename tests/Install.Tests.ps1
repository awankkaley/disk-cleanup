BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
    $script:installScript = Join-Path -Path $script:repoRoot -ChildPath 'install.ps1'
    $script:powershellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    $script:commandModes = @('scan', 'scan-only', 'deep', 'help')

    # The installer always runs in a child process against a sandboxed USERPROFILE and
    # with --local, so it never downloads anything and never sees the real profile.
    function Invoke-Installer {
        param([string[]]$Arguments)
        $output = @(& $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $script:installScript @Arguments)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($output | ForEach-Object { [string]$_ }) -join "`n") }
    }

    function Add-AgentMarker {
        param([string[]]$Relative)
        foreach ($item in $Relative) {
            [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $script:sandbox.Home -ChildPath $item))
        }
    }

    function Get-SkillDir {
        param([string]$AgentFolder)
        return (Join-Path -Path $script:sandbox.Home -ChildPath ($AgentFolder + '\skills\disk-cleanup'))
    }

    function Test-SkillInstalled {
        param([string]$AgentFolder)
        $skillDir = Get-SkillDir -AgentFolder $AgentFolder
        foreach ($relative in @('SKILL.md', 'LICENSE', 'scripts\cleanup.ps1', 'scripts\lib\Core.ps1')) {
            if (-not (Test-Path -LiteralPath (Join-Path -Path $skillDir -ChildPath $relative) -PathType Leaf)) { return $false }
        }
        return $true
    }

    function Get-CommandFile {
        param([string]$Agent)
        if ($Agent -eq 'gemini') {
            return (Join-Path -Path $script:sandbox.Home -ChildPath '.gemini\commands\disk-cleanup.toml')
        }
        return (Join-Path -Path $script:sandbox.Home -ChildPath '.config\opencode\commands\disk-cleanup.md')
    }

    # Folder that holds the namespaced command files (one per mode) of an agent.
    function Get-NamespaceDir {
        param([string]$Agent)
        if ($Agent -eq 'gemini') {
            return (Join-Path -Path $script:sandbox.Home -ChildPath '.gemini\commands\disk-cleanup')
        }
        return (Join-Path -Path $script:sandbox.Home -ChildPath '.config\opencode\commands\disk-cleanup')
    }

    function Get-CommandExtension {
        param([string]$Agent)
        if ($Agent -eq 'gemini') { return 'toml' }
        return 'md'
    }

    function Get-ChildName {
        param([string]$Directory)
        return @(Get-ChildItem -LiteralPath $Directory -Force | ForEach-Object { $_.Name })
    }

    function Set-ForeignFile {
        param([string]$Path, [string]$Text)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text)
    }
}

Describe 'install.ps1' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:canRun = (Test-WindowsHost) -and (Test-Path -LiteralPath $script:powershellExe)
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:documentFile = Join-Path -Path $script:sandbox.Home -ChildPath 'Documents\zqreport.docx'
        Add-SandboxFile -Path $script:documentFile
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'installs for the agents found on the machine and for no others' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude', '.cursor')

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot)

        $run.ExitCode | Should -Be 0
        Test-SkillInstalled -AgentFolder '.claude' | Should -BeTrue
        Test-SkillInstalled -AgentFolder '.cursor' | Should -BeTrue
        foreach ($absent in @('.gemini', '.copilot', '.agents', '.codex', '.config')) {
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath $absent) | Should -BeFalse
        }
        Test-Path -LiteralPath (Join-Path -Path (Get-SkillDir -AgentFolder '.claude') -ChildPath 'tests') | Should -BeFalse
        Test-Path -LiteralPath $script:documentFile | Should -BeTrue
    }

    It 'copies only SKILL.md, LICENSE and scripts, and nothing of the plugin packaging' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'claude')

        $run.ExitCode | Should -Be 0
        $names = @(Get-ChildName -Directory (Get-SkillDir -AgentFolder '.claude'))
        $names.Count | Should -Be 3
        foreach ($expected in @('SKILL.md', 'LICENSE', 'scripts')) {
            $names -contains $expected | Should -BeTrue
        }
        Test-Path -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath '.claude-plugin\plugin.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:repoRoot -ChildPath 'skills\scan\SKILL.md') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath '.claude\commands') | Should -BeFalse
    }

    It 'installs only for the agent named with --agent' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude', '.cursor')

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'cursor')

        $run.ExitCode | Should -Be 0
        Test-SkillInstalled -AgentFolder '.cursor' | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath '.claude\skills') | Should -BeFalse
    }

    It 'installs into the shared agents folder for codex' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'codex')

        $run.ExitCode | Should -Be 0
        Test-SkillInstalled -AgentFolder '.agents' | Should -BeTrue
    }

    It 'fails without touching anything when no agent is found' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot)

        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath '.claude') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath '.agents') | Should -BeFalse
    }

    It 'rejects an unknown agent name' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'zqnobody')

        $run.ExitCode | Should -Be 1
    }

    It 'replaces an earlier install when run again' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude')
        $first = Invoke-Installer -Arguments @('--local', $script:repoRoot)
        $stale = Join-Path -Path (Get-SkillDir -AgentFolder '.claude') -ChildPath 'scripts\zqstale.ps1'
        Add-SandboxFile -Path $stale
        $neighbour = Join-Path -Path $script:sandbox.Home -ChildPath '.claude\skills\zqother\SKILL.md'
        Add-SandboxFile -Path $neighbour

        $second = Invoke-Installer -Arguments @('--local', $script:repoRoot)

        $first.ExitCode | Should -Be 0
        $second.ExitCode | Should -Be 0
        Test-SkillInstalled -AgentFolder '.claude' | Should -BeTrue
        Test-Path -LiteralPath $stale | Should -BeFalse
        Test-Path -LiteralPath $neighbour | Should -BeTrue
    }

    It 'uninstalls only the disk-cleanup folder' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude', '.cursor')
        $null = Invoke-Installer -Arguments @('--local', $script:repoRoot)
        $neighbour = Join-Path -Path $script:sandbox.Home -ChildPath '.claude\skills\zqother\SKILL.md'
        Add-SandboxFile -Path $neighbour

        $run = Invoke-Installer -Arguments @('--uninstall')

        $run.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.claude') | Should -BeFalse
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.cursor') | Should -BeFalse
        Test-Path -LiteralPath $neighbour | Should -BeTrue
        Test-Path -LiteralPath $script:documentFile | Should -BeTrue
    }

    It 'uninstalls only for the agent named with --agent and succeeds when nothing is installed' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude', '.cursor')
        $null = Invoke-Installer -Arguments @('--local', $script:repoRoot)

        $run = Invoke-Installer -Arguments @('--uninstall', '--agent', 'cursor')
        $again = Invoke-Installer -Arguments @('--uninstall', '--agent', 'cursor')

        $run.ExitCode | Should -Be 0
        $again.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.cursor') | Should -BeFalse
        Test-SkillInstalled -AgentFolder '.claude' | Should -BeTrue
    }

    It 'refuses to <Action> a disk-cleanup folder that is not this skill' -ForEach @(
        @{ Action = 'replace'; Line = @('--agent', 'claude') }
        @{ Action = 'remove'; Line = @('--uninstall', '--agent', 'claude') }
    ) {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $foreign = Join-Path -Path (Get-SkillDir -AgentFolder '.claude') -ChildPath 'zqnotes.txt'
        Add-SandboxFile -Path $foreign
        $otherSkill = Join-Path -Path (Get-SkillDir -AgentFolder '.claude') -ChildPath 'SKILL.md'
        [System.IO.File]::WriteAllText($otherSkill, "---`nname: zqsomething-else`n---`n")
        $arguments = [string[]](@('--local', $script:repoRoot) + $Line)

        $run = Invoke-Installer -Arguments $arguments

        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath $foreign | Should -BeTrue
        [System.IO.File]::ReadAllText($otherSkill) | Should -Match 'zqsomething-else'
    }

    It 'installs a command file for gemini and opencode and for no other agent' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $run = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'claude,codex,cursor,gemini,copilot,opencode')

        $run.ExitCode | Should -Be 0
        foreach ($agent in @('gemini', 'opencode')) {
            $commandFile = Get-CommandFile -Agent $agent
            Test-Path -LiteralPath $commandFile -PathType Leaf | Should -BeTrue
            [System.IO.File]::ReadAllText($commandFile) | Should -Match 'disk-cleanup-skill:managed-command'
        }
        foreach ($agent in @('gemini', 'opencode')) {
            $namespaceDir = Get-NamespaceDir -Agent $agent
            $extension = Get-CommandExtension -Agent $agent
            @(Get-ChildName -Directory $namespaceDir).Count | Should -Be 4
            foreach ($mode in $script:commandModes) {
                $modeFile = Join-Path -Path $namespaceDir -ChildPath ($mode + '.' + $extension)
                Test-Path -LiteralPath $modeFile -PathType Leaf | Should -BeTrue
                $text = [System.IO.File]::ReadAllText($modeFile)
                $text | Should -Match 'disk-cleanup-skill:managed-command'
                $text.Contains('in the mode `' + $mode + '`:') | Should -BeTrue
            }
        }
        Test-SkillInstalled -AgentFolder '.gemini' | Should -BeTrue
        Test-SkillInstalled -AgentFolder '.config\opencode' | Should -BeTrue
        foreach ($absent in @('.claude\commands', '.cursor\commands', '.copilot\commands', '.agents\commands', '.codex', '.gemini\skills\disk-cleanup\commands', '.gemini\skills\disk-cleanup\skills', '.gemini\skills\disk-cleanup\.claude-plugin')) {
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Home -ChildPath $absent) | Should -BeFalse
        }
    }

    It 'uninstalls its own command files and keeps other commands' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $null = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'gemini,opencode')
        $neighbour = Join-Path -Path $script:sandbox.Home -ChildPath '.gemini\commands\zqother.toml'
        Set-ForeignFile -Path $neighbour -Text 'prompt = "zqmine"'
        $installedBefore = Test-Path -LiteralPath (Get-CommandFile -Agent 'gemini') -PathType Leaf

        $run = Invoke-Installer -Arguments @('--uninstall', '--agent', 'gemini')

        $installedBefore | Should -BeTrue
        $run.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Get-CommandFile -Agent 'gemini') | Should -BeFalse
        Test-Path -LiteralPath (Get-NamespaceDir -Agent 'gemini') | Should -BeFalse
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.gemini') | Should -BeFalse
        Test-Path -LiteralPath $neighbour | Should -BeTrue
        Test-Path -LiteralPath (Get-CommandFile -Agent 'opencode') -PathType Leaf | Should -BeTrue
        @(Get-ChildName -Directory (Get-NamespaceDir -Agent 'opencode')).Count | Should -Be 4
    }

    It 'never replaces or removes a file in the namespace subfolder that is not its own' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $namespaceDir = Get-NamespaceDir -Agent 'gemini'
        $foreignMode = Join-Path -Path $namespaceDir -ChildPath 'deep.toml'
        $foreignExtra = Join-Path -Path $namespaceDir -ChildPath 'zqmine.toml'
        Set-ForeignFile -Path $foreignMode -Text 'prompt = "zqdeep"'
        Set-ForeignFile -Path $foreignExtra -Text 'prompt = "zqextra"'

        $install = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'gemini')
        $afterInstall = [System.IO.File]::ReadAllText($foreignMode)
        $ownInstalled = Test-Path -LiteralPath (Join-Path -Path $namespaceDir -ChildPath 'scan.toml') -PathType Leaf
        $uninstall = Invoke-Installer -Arguments @('--uninstall', '--agent', 'gemini')

        $install.ExitCode | Should -Be 0
        $afterInstall | Should -Be 'prompt = "zqdeep"'
        $ownInstalled | Should -BeTrue
        $uninstall.ExitCode | Should -Be 0
        @(Get-ChildName -Directory $namespaceDir).Count | Should -Be 2
        [System.IO.File]::ReadAllText($foreignMode) | Should -Be 'prompt = "zqdeep"'
        [System.IO.File]::ReadAllText($foreignExtra) | Should -Be 'prompt = "zqextra"'
        Test-Path -LiteralPath (Get-CommandFile -Agent 'gemini') | Should -BeFalse
    }

    It 'never replaces or removes a command file of the same name that is not its own' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $geminiFile = Get-CommandFile -Agent 'gemini'
        $opencodeFile = Get-CommandFile -Agent 'opencode'
        Set-ForeignFile -Path $geminiFile -Text 'prompt = "zqmine"'
        Set-ForeignFile -Path $opencodeFile -Text 'zqmine'

        $install = Invoke-Installer -Arguments @('--local', $script:repoRoot, '--agent', 'gemini,opencode')
        $afterInstall = [System.IO.File]::ReadAllText($geminiFile)
        $skillInstalled = Test-SkillInstalled -AgentFolder '.gemini'
        $uninstall = Invoke-Installer -Arguments @('--uninstall', '--agent', 'gemini,opencode')

        $install.ExitCode | Should -Be 0
        $afterInstall | Should -Be 'prompt = "zqmine"'
        $skillInstalled | Should -BeTrue
        $uninstall.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($geminiFile) | Should -Be 'prompt = "zqmine"'
        [System.IO.File]::ReadAllText($opencodeFile) | Should -Be 'zqmine'
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.gemini') | Should -BeFalse
    }

    It 'aborts when the --local source is the install location itself' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        Add-AgentMarker -Relative @('.claude')
        $null = Invoke-Installer -Arguments @('--local', $script:repoRoot)
        $installed = Get-SkillDir -AgentFolder '.claude'

        $run = Invoke-Installer -Arguments @('--local', $installed, '--agent', 'claude')

        $run.ExitCode | Should -Be 1
        Test-SkillInstalled -AgentFolder '.claude' | Should -BeTrue
    }

    It 'aborts when the --local source contains the install location' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $source = Join-Path -Path $script:sandbox.Home -ChildPath '.claude\skills'
        Add-SandboxFile -Path (Join-Path -Path $source -ChildPath 'SKILL.md')
        Add-SandboxFile -Path (Join-Path -Path $source -ChildPath 'LICENSE')
        Add-SandboxFile -Path (Join-Path -Path $source -ChildPath 'scripts\zqscript.ps1')

        $run = Invoke-Installer -Arguments @('--local', $source, '--agent', 'claude')

        $run.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Get-SkillDir -AgentFolder '.claude') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $source -ChildPath 'scripts\zqscript.ps1') | Should -BeTrue
    }
}
