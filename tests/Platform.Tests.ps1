BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
}

Describe 'Invoke-Tool' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:toolPath = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqbin\zqtool.cmd'
        Mock Get-ToolPath { $script:toolPath }
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'reports a failure when the tool is not installed' {
        Mock Get-ToolPath { $null }

        $result = Invoke-Tool -Name 'zqtool' -Arguments @('anything')

        $result.ExitCode | Should -Not -Be 0
        @($result.Output).Count | Should -Be 0
        Test-Path -LiteralPath $script:sandbox.StateDir | Should -BeFalse
    }

    It 'runs the tool in the state directory with stdin closed and stderr discarded' {
        if (-not (Test-WindowsHost)) {
            Set-ItResult -Skipped -Because 'batch files only run on Windows'
            return
        }
        Add-SandboxBatchTool -Path $script:toolPath -Lines @(
            '@echo off', 'set /p zqline=', 'echo zqerr 1>&2', 'echo zqarg=%1', 'cd', 'exit /b 0'
        )
        $projectDir = Join-Path -Path $script:sandbox.Home -ChildPath 'zqproject'
        [void][System.IO.Directory]::CreateDirectory($projectDir)
        Push-Location -LiteralPath $projectDir
        try {
            $result = Invoke-Tool -Name 'zqtool' -Arguments @('zqfirst')
            $locationAfter = (Get-Location).ProviderPath
        } finally {
            Pop-Location
        }

        $result.ExitCode | Should -Be 0
        $lines = @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 2
        $lines[0].Trim() | Should -Be 'zqarg=zqfirst'
        Get-NormalizedPath -Path $lines[1].Trim() | Should -Be (Get-NormalizedPath -Path $script:sandbox.StateDir)
        ($result.Output -join '|') | Should -Not -Match 'zqerr'
        $locationAfter | Should -Be $projectDir
    }

    It 'returns the exit code of the tool' {
        if (-not (Test-WindowsHost)) {
            Set-ItResult -Skipped -Because 'batch files only run on Windows'
            return
        }
        Add-SandboxBatchTool -Path $script:toolPath -Lines @('@echo off', 'echo zqout', 'exit /b 3')

        $result = Invoke-Tool -Name 'zqtool' -Arguments @()

        $result.ExitCode | Should -Be 3
    }

    It 'gives up on a tool that runs past the timeout and reports a failure' {
        if (-not (Test-WindowsHost)) {
            Set-ItResult -Skipped -Because 'batch files only run on Windows'
            return
        }
        Add-SandboxBatchTool -Path $script:toolPath -Lines @('@echo off', 'ping -n 8 127.0.0.1 >nul', 'echo zqlate')
        Mock Get-ToolTimeoutMillisecond { 500 }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        $result = Invoke-Tool -Name 'zqtool' -Arguments @()

        $watch.Stop()
        $result.ExitCode | Should -Not -Be 0
        @($result.Output).Count | Should -Be 0
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 5
    }

    It 'refuses to run a tool when the state directory is a link' {
        Add-SandboxBatchTool -Path $script:toolPath -Lines @('@echo off', 'echo zqout')
        Add-SandboxJunction -Link $script:sandbox.StateDir -Target $script:sandbox.Outside

        $result = Invoke-Tool -Name 'zqtool' -Arguments @()

        $result.ExitCode | Should -Not -Be 0
    }
}

Describe 'tool clean result on timeout' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        Mock Test-AppRunning { $false }
        Mock Get-RunningPackageFamilyList { @() }
        Mock Get-AccountProfilePath { $null }
        Mock Get-DiskInfo { [pscustomobject]@{ TotalBytes = [long]2000000; FreeBytes = [long]1000000 } }
        Mock Get-RecycleBinInfo { [pscustomobject]@{ Available = $true; Bytes = [long]0; Items = 0 } }
        Mock Invoke-RecycleBinEmpty { $true }
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'maps a timed-out clean command to failed with TOOL_FAILED' {
        $script:goDir = Join-Path -Path $script:sandbox.Local -ChildPath 'go-build'
        Add-SandboxFile -Path (Join-Path -Path $script:goDir -ChildPath 'zqobject') -SizeBytes 19
        Mock Get-ToolPath { $null }
        Mock Get-ToolPath { 'C:\zqtools\go.exe' } -ParameterFilter { $Name -eq 'go' }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = -1; Output = @() } }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:goDir) } } -ParameterFilter {
            ($Name -eq 'go') -and (($Arguments -join ' ') -eq 'env GOCACHE')
        }
        $token = [string](Invoke-CleanupJson -Arguments @('scan')).Data.token

        $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'go-cache')

        $result = Get-ResultEntry -Data $run.Data -Id 'go-cache'
        $result.status | Should -Be 'failed'
        $result.error_code | Should -Be 'TOOL_FAILED'
        Test-Path -LiteralPath (Join-Path -Path $script:goDir -ChildPath 'zqobject') | Should -BeTrue
    }
}

Describe 'review platform functions' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:sample = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos\zqsample.bin'
        Add-SandboxFile -Path $script:sample -SizeBytes 4096
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'does not open the report when the skip switch is set' {
        $env:DISK_CLEANUP_SKIP_REPORT_OPEN = '1'

        Open-ReviewReport -Path $script:sample | Should -BeFalse
    }

    It 'moves nothing and reports a failure when the recycle skip switch is set' {
        $env:DISK_CLEANUP_SKIP_RECYCLE = '1'

        Send-FileToRecycleBin -Path $script:sample | Should -BeExactly 'failed'
        Test-Path -LiteralPath $script:sample | Should -BeTrue
    }

    It 'keeps the recycle result names and the switch value stable' {
        $script:RECYCLE_FAILED | Should -BeExactly 'failed'
        $script:RECYCLE_DENIED | Should -BeExactly 'denied'
        $script:RECYCLE_TRASHED | Should -BeExactly 'trashed'
        $script:SKIP_SEAM_VALUE | Should -BeExactly '1'
    }

    It 'recognizes an access-denied error at any depth' {
        $denied = New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'zqdenied'
        $wrapped = New-Object -TypeName System.InvalidOperationException -ArgumentList 'zqouter', $denied
        $other = New-Object -TypeName System.IO.IOException -ArgumentList 'zqbusy'

        Test-AccessDeniedError -Exception $denied | Should -BeTrue
        Test-AccessDeniedError -Exception $wrapped | Should -BeTrue
        Test-AccessDeniedError -Exception $other | Should -BeFalse
        Test-AccessDeniedError -Exception $null | Should -BeFalse
    }

    It 'measures what a plain file occupies on disk' {
        if (-not (Test-WindowsHost)) {
            Set-ItResult -Skipped -Because 'the size on disk is asked from Windows'
            return
        }

        Get-AllocatedFileSize -Path $script:sample | Should -Be 4096
    }

    It 'returns nothing for a file it cannot measure' {
        Get-AllocatedFileSize -Path (Join-Path -Path $script:sandbox.Home -ChildPath 'zqmissing.bin') | Should -BeNullOrEmpty
    }

    It 'answers whether the Recycle Bin can hold a file without ever failing' {
        $tooBig = Test-RecycleBinCanHold -Path $script:sample -Bytes ([long]::MaxValue)
        $tiny = Test-RecycleBinCanHold -Path $script:sample -Bytes 1

        $tooBig | Should -BeFalse
        $tiny | Should -BeOfType [bool]
    }

    It 'says no when the Recycle Bin is switched off by policy or for the volume' {
        Mock Test-RecyclePolicyOff { $true }
        Test-RecycleBinCanHold -Path $script:sample -Bytes 1 | Should -BeFalse

        Mock Test-RecyclePolicyOff { $false }
        Mock Get-RecycleVolumeLimit { [long]0 }
        Test-RecycleBinCanHold -Path $script:sample -Bytes 1 | Should -BeFalse
    }

    It 'compares the file with the capacity of the volume: <Bytes> bytes fit is <Expected>' -ForEach @(
        @{ Bytes = 1048576; Expected = $true }
        @{ Bytes = 5242880; Expected = $true }
        @{ Bytes = 5242881; Expected = $false }
    ) {
        Mock Test-RecyclePolicyOff { $false }
        Mock Get-RecycleVolumeLimit { [long]5242880 }

        Test-RecycleBinCanHold -Path $script:sample -Bytes $Bytes | Should -Be $Expected
    }

    It 'says no when the settings cannot be read' {
        Mock Test-RecyclePolicyOff { throw 'zqregistry' }

        Test-RecycleBinCanHold -Path $script:sample -Bytes 1 | Should -BeFalse
    }
}
