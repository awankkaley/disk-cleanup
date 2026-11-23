BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
}

Describe 'command line contract' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:fakeBin = [pscustomobject]@{ Available = $true; Bytes = [long]0; Items = 0 }
        Mock Test-AppRunning { $false }
        Mock Get-RunningPackageFamilyList { @() }
        Mock Get-AccountProfilePath { $null }
        Mock Get-DiskInfo { [pscustomobject]@{ TotalBytes = [long]2000000; FreeBytes = [long]1000000 } }
        Mock Get-RecycleBinInfo { $script:fakeBin }
        Mock Invoke-RecycleBinEmpty { $true }
        Mock Get-ToolPath { $null }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 1; Output = @() } }
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'reports <Code> with exit code <Status> for "<Line>"' -ForEach @(
        @{ Line = ''; Code = 'USAGE'; Status = 2 }
        @{ Line = 'purge'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'SCAN'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan --everything'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan --empty-trash'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan --min-age-days'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan --deep --deep'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan stray'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'clean --token abcdef12'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'clean --token --categories temp-files'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'clean --token abcdef12 --categories ,'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'clean --categories temp-files'; Code = 'TOKEN_MISSING'; Status = 1 }
        @{ Line = 'scan --min-age-days soon'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --min-age-days 0'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --min-age-days -3'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories temp-files --min-idle-days 29'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories all'; Code = 'UNKNOWN_CATEGORY'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories *'; Code = 'UNKNOWN_CATEGORY'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories logs'; Code = 'UNKNOWN_CATEGORY'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories Temp-Files'; Code = 'UNKNOWN_CATEGORY'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories trash'; Code = 'TRASH_FLAG_REQUIRED'; Status = 1 }
        @{ Line = 'clean --token not-a-token --categories temp-files'; Code = 'TOKEN_INVALID'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories temp-files'; Code = 'TOKEN_INVALID'; Status = 1 }
        @{ Line = 'scan --target-gb'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'scan --target-gb 0'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --target-gb 10001'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --target-gb 1.5'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --target-gb -4'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'scan --target-gb ten'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'clean --token abcdef12 --categories temp-files --target-gb 5'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'REVIEW'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review --token abcdef12'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review --deep'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review stray'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review --min-size-mb'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review --min-size-mb 9'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'review --min-size-mb big'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'review --min-size-mb 99999999'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'review --downloads-age-days 6'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'review --downloads-age-days -90'; Code = 'INVALID_ARGUMENT'; Status = 1 }
        @{ Line = 'review-apply'; Code = 'TOKEN_MISSING'; Status = 1 }
        @{ Line = 'review-apply --categories temp-files'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review-apply --token abcdef12 --empty-trash'; Code = 'USAGE'; Status = 2 }
        @{ Line = 'review-apply --token not-a-token'; Code = 'TOKEN_INVALID'; Status = 1 }
        @{ Line = 'review-apply --token ABCDEF12'; Code = 'TOKEN_INVALID'; Status = 1 }
        @{ Line = 'review-apply --token abcdef12'; Code = 'TOKEN_INVALID'; Status = 1 }
    ) {
        $arguments = [string[]]@($Line.Split(' ') | Where-Object { $_.Length -gt 0 })

        $run = Invoke-CleanupJson -Arguments $arguments

        $run.ExitCode | Should -Be $Status
        $run.Data.schema_version | Should -Be 1
        $run.Data.error.code | Should -Be $Code
        $run.Data.error.message | Should -Not -BeNullOrEmpty
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'never echoes an unknown category id' {
        $run = Invoke-CleanupJson -Arguments @('clean', '--token', 'abcdef12', '--categories', 'temp-files,..\..\Documents')

        $run.Data.error.code | Should -Be 'UNKNOWN_CATEGORY'
        $run.Json | Should -Not -Match 'Documents'
    }

    It 'prints the version as a JSON document' {
        $run = Invoke-CleanupJson -Arguments @('--version')

        $run.ExitCode | Should -Be 0
        $run.Data.command | Should -Be 'version'
        $run.Data.version | Should -Match '^[0-9]+\.[0-9]+\.[0-9]+$'
    }

    It 'prints help as a JSON document without creating the state directory' {
        $run = Invoke-CleanupJson -Arguments @('--help')

        $run.ExitCode | Should -Be 0
        $run.Data.command | Should -Be 'help'
        @($run.Data.usage).Count | Should -BeGreaterThan 1
        Test-Path -LiteralPath $script:sandbox.StateDir | Should -BeFalse
    }

    It 'accepts the --flag=value form' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--min-age-days=30')

        $run.ExitCode | Should -Be 0
        $run.Data.command | Should -Be 'scan'
    }

    It 'parses scan flags into options' {
        $options = ConvertFrom-CliArgument -Arguments @('scan', '--deep', '--min-age-days', '14')

        $options.Command | Should -Be 'scan'
        $options.Deep | Should -BeTrue
        $options.MinAgeDays | Should -Be 14
    }

    It 'parses the scan target and the review flags into options' {
        $scan = ConvertFrom-CliArgument -Arguments @('scan', '--target-gb', '25')
        $plain = ConvertFrom-CliArgument -Arguments @('scan')
        $defaults = ConvertFrom-CliArgument -Arguments @('review')
        $review = ConvertFrom-CliArgument -Arguments @('review', '--min-size-mb=10', '--downloads-age-days', '7')
        $apply = ConvertFrom-CliArgument -Arguments @('review-apply', '--token', 'abcdef12')

        $scan.TargetGb | Should -Be 25
        $plain.TargetGb | Should -Be 0
        $defaults.Command | Should -Be 'review'
        $defaults.MinSizeMb | Should -Be 100
        $defaults.DownloadsAgeDays | Should -Be 90
        $review.MinSizeMb | Should -Be 10
        $review.DownloadsAgeDays | Should -Be 7
        $apply.Command | Should -Be 'review-apply'
        $apply.Token | Should -Be 'abcdef12'
    }

    It 'lists every command in the help document' {
        $usage = (Invoke-CleanupJson -Arguments @('--help')).Data.usage -join '|'

        $usage | Should -Match 'cleanup scan .*--target-gb N'
        $usage | Should -Match 'cleanup review \['
        $usage | Should -Match 'cleanup review-apply --token ID'
    }

    It 'reports version 1.2.0' {
        (Invoke-CleanupJson -Arguments @('--version')).Data.version | Should -Be '1.2.0'
    }

    It 'parses clean flags into options' {
        $line = @('clean', '--token', 'abcdef12', '--categories', 'temp-files, crash-dumps,temp-files', '--log')

        $options = ConvertFrom-CliArgument -Arguments $line

        $options.Token | Should -Be 'abcdef12'
        @($options.Categories).Count | Should -Be 2
        $options.Categories | Should -Contain 'crash-dumps'
        $options.Log | Should -BeTrue
        $options.EmptyTrash | Should -BeFalse
        $options.MinIdleDays | Should -Be 30
    }

    It 'rejects a --projects-dir that does not exist' {
        $missing = Join-Path -Path $script:sandbox.Home -ChildPath 'zqmissing'

        $run = Invoke-CleanupJson -Arguments @('scan', '--deep', '--projects-dir', $missing)

        $run.Data.error.code | Should -Be 'INVALID_ARGUMENT'
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'rejects a --projects-dir outside the user profile' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--deep', '--projects-dir', $script:sandbox.Outside)

        $run.Data.error.code | Should -Be 'INVALID_ARGUMENT'
    }

    It 'rejects a relative --projects-dir' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--deep', '--projects-dir', 'zqrelative\work')

        $run.Data.error.code | Should -Be 'INVALID_ARGUMENT'
    }

    It 'rejects a --projects-dir inside <Name>' -ForEach @(
        @{ Name = 'a dot-directory'; Relative = '.zqhidden\work' }
        @{ Name = 'AppData'; Relative = 'AppData\Local\zqwork' }
        @{ Name = 'Library'; Relative = 'Library\zqwork' }
        @{ Name = 'node_modules'; Relative = 'zqcode\node_modules\zqwork' }
    ) {
        $directory = Join-Path -Path $script:sandbox.Home -ChildPath $Relative
        [void][System.IO.Directory]::CreateDirectory($directory)

        $run = Invoke-CleanupJson -Arguments @('scan', '--deep', '--projects-dir', $directory)

        $run.Data.error.code | Should -Be 'INVALID_ARGUMENT'
    }

    It 'accepts a --projects-dir inside the user profile, including the ~ shortcut' {
        [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode'))

        $run = Invoke-CleanupJson -Arguments @('scan', '--deep', '--projects-dir', '~\zqcode')

        $run.ExitCode | Should -Be 0
    }

    It 'refuses to run on an unsupported platform' {
        Mock Test-SupportedPlatform { $false }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 1
        $run.Data.error.code | Should -Be 'UNSUPPORTED_PLATFORM'
        Test-Path -LiteralPath $script:sandbox.StateDir | Should -BeFalse
    }

    It 'refuses a <Name> user profile' -ForEach @(
        @{ Name = 'relative'; Value = 'zqrelative\home' }
        @{ Name = 'missing'; Value = 'C:\zqabsent\zqnobody' }
        @{ Name = 'drive root'; Value = 'C:\' }
        @{ Name = 'empty'; Value = '' }
    ) {
        $env:USERPROFILE = $Value

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 1
        $run.Data.error.code | Should -Be 'INTERNAL'
        $run.Json | Should -Not -Match 'zq'
    }

    It 'refuses a <Name> <Variable> before measuring anything' -ForEach @(
        @{ Variable = 'LOCALAPPDATA'; Name = 'drive root'; Value = 'C:\' }
        @{ Variable = 'LOCALAPPDATA'; Name = 'single-segment'; Value = [string]$env:SystemRoot }
        @{ Variable = 'LOCALAPPDATA'; Name = 'relative'; Value = 'zqrelative\local' }
        @{ Variable = 'LOCALAPPDATA'; Name = 'empty'; Value = '' }
        @{ Variable = 'APPDATA'; Name = 'drive root'; Value = 'C:\' }
        @{ Variable = 'APPDATA'; Name = 'single-segment'; Value = [string]$env:SystemRoot }
    ) {
        Mock Measure-Target { [pscustomobject]@{ Bytes = [long]0; Files = 0; Denied = $false } }
        [System.Environment]::SetEnvironmentVariable($Variable, $Value)

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 1
        $run.Data.error.code | Should -Be 'INTERNAL'
        Should -Invoke Measure-Target -Times 0 -Exactly
        $run.Json | Should -Not -Match 'zq'
    }

    It 'still runs when APPDATA is not set' {
        $env:APPDATA = ''

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
    }

    It 'refuses a user profile that lies inside the real profile of the account' {
        Mock Get-AccountProfilePath { $script:sandbox.Base }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 1
        $run.Data.error.code | Should -Be 'INTERNAL'
        Test-Path -LiteralPath $script:sandbox.StateDir | Should -BeFalse
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'accepts a user profile that <Name>' -ForEach @(
        @{ Name = 'is the real profile of the account'; Kind = 'same' }
        @{ Name = 'lies outside the real profile of the account'; Kind = 'elsewhere' }
    ) {
        $script:accountProfile = $script:sandbox.Home
        if ($Kind -eq 'elsewhere') { $script:accountProfile = $script:sandbox.Outside }
        Mock Get-AccountProfilePath { $script:accountProfile }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
    }
}
