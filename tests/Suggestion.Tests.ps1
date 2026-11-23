BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    $script:megabyte = [long]1048576
    $script:gigabyte = [long]1073741824

    function Get-FakeEntry {
        param([string]$Id, [int]$Cost, $Bytes, [string]$Status = 'ok', [bool]$Recommended = $true)
        return [ordered]@{
            id = $Id; status = $Status; recommended = $Recommended; size_bytes = $Bytes; rebuild_cost = $Cost
        }
    }
}

Describe 'scan --target-gb' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        Add-SandboxCache -Sandbox $script:sandbox
        $script:fakeBin = [pscustomobject]@{ Available = $true; Bytes = [long]900; Items = 3 }
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

    It 'leaves the suggestion out without the flag' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        @($run.Data.PSObject.Properties | ForEach-Object { $_.Name }) | Should -Not -Contain 'suggestion'
        $run.Json | Should -Not -Match 'suggestion'
    }

    It 'gives every category a numeric rebuild cost of 1, 2 or 3' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        foreach ($entry in $run.Data.categories) { @(1, 2, 3) | Should -Contain $entry.rebuild_cost }
        $run.Json | Should -Not -Match '"rebuild_cost":"'
        (Get-CategoryEntry -Data $run.Data -Id 'temp-files').rebuild_cost | Should -Be 1
        (Get-CategoryEntry -Data $run.Data -Id 'browser-chrome').rebuild_cost | Should -Be 1
        (Get-CategoryEntry -Data $run.Data -Id 'app-caches').rebuild_cost | Should -Be 2
        (Get-CategoryEntry -Data $run.Data -Id 'store-app-caches').rebuild_cost | Should -Be 2
        (Get-CategoryEntry -Data $run.Data -Id 'docker-dangling').rebuild_cost | Should -Be 2
        (Get-CategoryEntry -Data $run.Data -Id 'trash').rebuild_cost | Should -Be 2
        (Get-CategoryEntry -Data $run.Data -Id 'cargo-cache').rebuild_cost | Should -Be 3
        (Get-CategoryEntry -Data $run.Data -Id 'gradle-cache').rebuild_cost | Should -Be 3
    }

    It 'lists every candidate, cheapest rebuild first and largest first, when the target is out of reach' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--target-gb', '1')

        $run.ExitCode | Should -Be 0
        $suggestion = $run.Data.suggestion
        $suggestion.target_bytes | Should -Be $script:gigabyte
        $suggestion.reaches_target | Should -BeFalse
        $suggestion.total_bytes | Should -Be 590
        $expected = 'browser-chrome,temp-files,crash-dumps,thumbnail-cache,app-caches,store-app-caches,cargo-cache,gradle-cache'
        (@($suggestion.category_ids) -join ',') | Should -Be $expected
        @($suggestion.category_ids) | Should -Not -Contain 'trash'
        (@($suggestion.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') |
            Should -Be 'target_bytes,category_ids,total_bytes,reaches_target'
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'stops at the first category that reaches the target and keeps the id list an array' {
        Mock Measure-Target { [pscustomobject]@{ Bytes = [long]800000000; Files = 3; Denied = $false } }

        $run = Invoke-CleanupJson -Arguments @('scan', '--target-gb', '1')

        $run.Data.suggestion.reaches_target | Should -BeTrue
        $run.Data.suggestion.total_bytes | Should -Be 3200000000
        $run.Json | Should -Match '"category_ids":\["browser-chrome"\]'
        $run.Json | Should -Match '"target_bytes":1073741824[,}]'
        $run.Json | Should -Match '"reaches_target":true'
    }

    It 'returns an empty array when nothing can be suggested' {
        Mock Measure-Target { [pscustomobject]@{ Bytes = [long]0; Files = 0; Denied = $false } }

        $run = Invoke-CleanupJson -Arguments @('scan', '--target-gb', '10000')

        $run.Json | Should -Match '"category_ids":\[\]'
        $run.Data.suggestion.total_bytes | Should -Be 0
        $run.Data.suggestion.reaches_target | Should -BeFalse
        $run.Data.suggestion.target_bytes | Should -Be (10000 * $script:gigabyte)
    }

    It 'approves nothing: clean still needs explicit categories and the token' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--target-gb', '1')
        $before = (Get-SandboxFileList -Root $script:sandbox.Base) -join '|'

        $clean = Invoke-CleanupJson -Arguments @('clean', '--token', [string]$run.Data.token)

        $clean.Data.error.code | Should -Be 'USAGE'
        ((Get-SandboxFileList -Root $script:sandbox.Base) -join '|') | Should -Be $before
    }

    It 'still lets the scan token clean an explicit category' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--target-gb', '3')

        $clean = Invoke-CleanupJson -Arguments @('clean', '--token', [string]$run.Data.token, '--categories', 'temp-files')

        (Get-ResultEntry -Data $clean.Data -Id 'temp-files').status | Should -Be 'cleaned'
    }
}

Describe 'Get-ScanSuggestion' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:entries = @(
            (Get-FakeEntry -Id 'small-cheap' -Cost 1 -Bytes (600 * $script:megabyte)),
            (Get-FakeEntry -Id 'big-cheap' -Cost 1 -Bytes (900 * $script:megabyte)),
            (Get-FakeEntry -Id 'huge-costly' -Cost 3 -Bytes (50 * $script:gigabyte)),
            (Get-FakeEntry -Id 'medium' -Cost 2 -Bytes (5 * $script:gigabyte)),
            (Get-FakeEntry -Id 'not-recommended' -Cost 1 -Bytes (90 * $script:gigabyte) -Recommended $false),
            (Get-FakeEntry -Id 'not-ok' -Cost 1 -Bytes (90 * $script:gigabyte) -Status 'skipped_running'),
            (Get-FakeEntry -Id 'unknown-size' -Cost 1 -Bytes $null),
            (Get-FakeEntry -Id 'zero' -Cost 1 -Bytes ([long]0))
        )
    }

    It 'takes <Expected> for a target of <Target> GB' -ForEach @(
        @{ Target = 1; Expected = 'big-cheap,small-cheap'; Reaches = $true }
        @{ Target = 2; Expected = 'big-cheap,small-cheap,medium'; Reaches = $true }
        @{ Target = 7; Expected = 'big-cheap,small-cheap,medium,huge-costly'; Reaches = $true }
        @{ Target = 100; Expected = 'big-cheap,small-cheap,medium,huge-costly'; Reaches = $false }
    ) {
        $suggestion = Get-ScanSuggestion -Entries $script:entries -TargetGb $Target

        ($suggestion['category_ids'] -join ',') | Should -Be $Expected
        $suggestion['reaches_target'] | Should -Be $Reaches
        $suggestion['target_bytes'] | Should -Be ($Target * $script:gigabyte)
    }

    It 'sums exactly the categories it names' {
        $suggestion = Get-ScanSuggestion -Entries $script:entries -TargetGb 1

        $suggestion['total_bytes'] | Should -Be (1500 * $script:megabyte)
        $suggestion['total_bytes'] | Should -BeOfType [long]
        (ConvertTo-OutputJson -Document $suggestion) | Should -Match '"category_ids":\["big-cheap","small-cheap"\]'
    }

    It 'keeps catalog order between equal categories' {
        $equal = @(
            (Get-FakeEntry -Id 'first' -Cost 1 -Bytes (700 * $script:megabyte)),
            (Get-FakeEntry -Id 'second' -Cost 1 -Bytes (700 * $script:megabyte))
        )

        $suggestion = Get-ScanSuggestion -Entries $equal -TargetGb 1

        ($suggestion['category_ids'] -join ',') | Should -Be 'first,second'
    }
}
