BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
    $script:installScript = Join-Path -Path $script:repoRoot -ChildPath 'install.ps1'
    $script:powershellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'

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
