BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
    $script:entryScript = Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1'
    $script:powershellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'

    # Runs the real script in a child Windows PowerShell, so StrictMode, the exit code
    # and the single stdout document are exactly what an agent would get.
    function Invoke-CleanupProcess {
        param([string[]]$Arguments)
        $output = @(& $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $script:entryScript @Arguments)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = [string[]]@($output | ForEach-Object { [string]$_ }) }
    }
}

Describe 'cleanup.ps1 in a child process' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:externalRoot = Get-ExternalSandboxRoot
        $script:canRun = (Test-WindowsHost) -and (Test-Path -LiteralPath $script:powershellExe) -and
            ($null -ne $script:externalRoot)
        $script:savedPath = $env:PATH
        $script:sandbox = $null
        if ($script:canRun) {
            $script:sandbox = Initialize-Sandbox -Root $script:externalRoot
            Add-SandboxCache -Sandbox $script:sandbox
            $script:sentinels = @(Add-SandboxSentinel -Sandbox $script:sandbox)
            # No developer tool may be found, so nothing real is ever started.
            $env:PATH = [System.Environment]::SystemDirectory
        }
    }

    AfterEach {
        $env:PATH = $script:savedPath
        Restore-SandboxEnvironment
        if (($null -ne $script:sandbox) -and [System.IO.Directory]::Exists($script:sandbox.Base)) {
            [System.IO.Directory]::Delete($script:sandbox.Base, $true)
        }
    }

    It 'scans and then cleans a sandboxed profile, printing one private JSON document each time' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'this needs Windows PowerShell and a folder outside the real user profile'
            return
        }
        $oldTemp = Join-Path -Path $script:sandbox.Temp -ChildPath 'zqold.tmp'
        $freshTemp = Join-Path -Path $script:sandbox.Temp -ChildPath 'zqfresh.tmp'
        $oldDump = Join-Path -Path $script:sandbox.Local -ChildPath 'CrashDumps\zqold.dmp'

        $scan = Invoke-CleanupProcess -Arguments @('scan')

        $scan.ExitCode | Should -Be 0
        $scan.Lines.Count | Should -Be 1
        $scanData = ConvertFrom-Json -InputObject $scan.Lines[0]
        $scanData.command | Should -Be 'scan'
        $scanData.token | Should -MatchExactly '^[0-9a-f]{8}$'
        $temp = Get-CategoryEntry -Data $scanData -Id 'temp-files'
        $temp.status | Should -Be 'ok'
        $temp.size_bytes | Should -Be 100
        (Get-CategoryEntry -Data $scanData -Id 'crash-dumps').status | Should -Be 'ok'
        (Get-CategoryEntry -Data $scanData -Id 'npm-cache').status | Should -Be 'not_found'
        Test-Path -LiteralPath $oldTemp | Should -BeTrue
        Assert-PrivateOutput -Json $scan.Lines[0] -Sandbox $script:sandbox

        $clean = Invoke-CleanupProcess -Arguments @(
            'clean', '--token', [string]$scanData.token, '--categories', 'temp-files,crash-dumps'
        )

        $clean.ExitCode | Should -Be 0
        $clean.Lines.Count | Should -Be 1
        $cleanData = ConvertFrom-Json -InputObject $clean.Lines[0]
        $cleanData.command | Should -Be 'clean'
        $cleanData.freed_total_bytes | Should -Be 170
        foreach ($result in $cleanData.results) {
            $result.status | Should -Be 'cleaned'
            $result.error_code | Should -BeNullOrEmpty
        }
        @($cleanData.results).Count | Should -Be 2
        Test-Path -LiteralPath $oldTemp | Should -BeFalse
        Test-Path -LiteralPath $oldDump | Should -BeFalse
        Test-Path -LiteralPath $freshTemp | Should -BeTrue
        foreach ($sentinel in $script:sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
        Test-Path -LiteralPath $script:sandbox.StateFile | Should -BeFalse
        Assert-PrivateOutput -Json $clean.Lines[0] -Sandbox $script:sandbox
    }

    It 'exits 1 with a JSON error when the token is reused' {
        if (-not $script:canRun) {
            Set-ItResult -Skipped -Because 'this needs Windows PowerShell and a folder outside the real user profile'
            return
        }
        $scan = Invoke-CleanupProcess -Arguments @('scan')
        $token = [string](ConvertFrom-Json -InputObject $scan.Lines[0]).token
        $first = Invoke-CleanupProcess -Arguments @('clean', '--token', $token, '--categories', 'temp-files')

        $second = Invoke-CleanupProcess -Arguments @('clean', '--token', $token, '--categories', 'temp-files')

        $first.ExitCode | Should -Be 0
        $second.ExitCode | Should -Be 1
        $second.Lines.Count | Should -Be 1
        (ConvertFrom-Json -InputObject $second.Lines[0]).error.code | Should -Be 'TOKEN_INVALID'
        Assert-PrivateOutput -Json $second.Lines[0] -Sandbox $script:sandbox
    }
}
