BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    $script:expectedIds = @(
        'app-caches', 'temp-files', 'thumbnail-cache', 'crash-dumps', 'store-app-caches', 'trash',
        'browser-chrome', 'browser-edge', 'browser-firefox', 'browser-brave', 'browser-opera', 'browser-arc',
        'npm-cache', 'yarn-cache', 'pnpm-store', 'pip-cache', 'gradle-cache', 'cargo-cache', 'go-cache',
        'docker-dangling'
    )
    $script:scanStatuses = @(
        'ok', 'empty', 'not_found', 'skipped_running', 'skipped_needs_admin', 'skipped_no_permission', 'unavailable'
    )
    $script:entryFields = @(
        'id', 'label', 'group', 'size_bytes', 'item_count', 'status', 'recommended', 'risk', 'impact', 'requires_flag',
        'rebuild_cost'
    )
}

Describe 'scan' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        Add-SandboxCache -Sandbox $script:sandbox
        $script:sentinels = @(Add-SandboxSentinel -Sandbox $script:sandbox)
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

    It 'prints one JSON document that matches the schema' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
        @($run.Json -split "`n").Count | Should -Be 1
        $run.Data.schema_version | Should -Be 1
        $run.Data.command | Should -Be 'scan'
        $run.Data.platform | Should -Be 'windows'
        $run.Data.token | Should -MatchExactly '^[0-9a-f]{8}$'
        $run.Data.token_expires_in_seconds | Should -Be 900
        $run.Data.disk.total_bytes | Should -Be 2000000
        $run.Data.disk.free_bytes | Should -Be 1000000
        $run.Json | Should -Match '"categories":\['
        $run.Json | Should -Match '"size_bytes":200[,}]'
        $run.Json | Should -Not -Match '"(size_bytes|item_count|recommended_total_bytes)":"'
    }

    It 'lists every Windows category once, in the fixed order, with every field' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        $ids = @($run.Data.categories | ForEach-Object { $_.id })
        ($ids -join ',') | Should -Be ($script:expectedIds -join ',')
        foreach ($entry in $run.Data.categories) {
            $names = @($entry.PSObject.Properties | ForEach-Object { $_.Name })
            ($names -join ',') | Should -Be ($script:entryFields -join ',')
            $script:scanStatuses | Should -Contain $entry.status
            @('system', 'browser', 'developer', 'projects') | Should -Contain $entry.group
            @('safe', 'rebuild_needed', 'irreversible') | Should -Contain $entry.risk
            $entry.recommended | Should -Be ($entry.risk -eq 'safe')
            $entry.label | Should -Not -BeNullOrEmpty
            $entry.impact | Should -Not -BeNullOrEmpty
        }
    }

    It 'measures <Id> as <Bytes> bytes in <Files> files' -ForEach @(
        @{ Id = 'browser-chrome'; Bytes = 200; Files = 4 }
        @{ Id = 'temp-files'; Bytes = 100; Files = 2 }
        @{ Id = 'crash-dumps'; Bytes = 70; Files = 1 }
        @{ Id = 'thumbnail-cache'; Bytes = 50; Files = 2 }
        @{ Id = 'store-app-caches'; Bytes = 25; Files = 2 }
        @{ Id = 'app-caches'; Bytes = 43; Files = 2 }
        @{ Id = 'gradle-cache'; Bytes = 33; Files = 1 }
        @{ Id = 'cargo-cache'; Bytes = 69; Files = 2 }
    ) {
        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id $Id
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be $Bytes
        $entry.item_count | Should -Be $Files
        $entry.requires_flag | Should -BeNullOrEmpty
    }

    It 'reports <Id> as <Status> when nothing is installed' -ForEach @(
        @{ Id = 'browser-firefox'; Status = 'not_found' }
        @{ Id = 'browser-edge'; Status = 'not_found' }
        @{ Id = 'browser-arc'; Status = 'not_found' }
        @{ Id = 'npm-cache'; Status = 'not_found' }
        @{ Id = 'go-cache'; Status = 'not_found' }
        @{ Id = 'docker-dangling'; Status = 'not_found' }
        @{ Id = 'trash'; Status = 'empty' }
    ) {
        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id $Id).status | Should -Be $Status
    }

    It 'sums recommended_total_bytes over ok and recommended categories only' {
        $script:fakeBin = [pscustomobject]@{ Available = $true; Bytes = [long]900; Items = 3 }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.Data.recommended_total_bytes | Should -Be 590
    }

    It 'deletes nothing' {
        $before = (Get-SandboxFileList -Root $script:sandbox.Base) -join '|'

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
        $after = @(Get-SandboxFileList -Root $script:sandbox.Base | Where-Object { $_ -ne $script:sandbox.StateFile })
        ($after -join '|') | Should -Be $before
        Should -Invoke Invoke-RecycleBinEmpty -Times 0 -Exactly
    }

    It 'keeps paths, fixture names and user names out of stdout' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'stores the token and the ok categories in the state file' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--min-age-days', '9')

        $state = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:sandbox.StateFile))
        $state.token | Should -Be $run.Data.token
        $state.min_age_days | Should -Be 9
        $state.deep | Should -BeFalse
        $state.categories | Should -Contain 'browser-chrome'
        $state.categories | Should -Not -Contain 'browser-firefox'
    }

    It 'applies --min-age-days to temporary files and crash dumps' {
        $run = Invoke-CleanupJson -Arguments @('scan', '--min-age-days', '45')

        $temp = Get-CategoryEntry -Data $run.Data -Id 'temp-files'
        $temp.size_bytes | Should -Be 60
        $temp.item_count | Should -Be 1
        (Get-CategoryEntry -Data $run.Data -Id 'crash-dumps').status | Should -Be 'empty'
        (Get-CategoryEntry -Data $run.Data -Id 'browser-chrome').size_bytes | Should -Be 200
    }

    It 'skips a browser that is running' {
        Mock Test-AppRunning { $true } -ParameterFilter { $Names -contains 'chrome' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'browser-chrome'
        $entry.status | Should -Be 'skipped_running'
        $entry.size_bytes | Should -Be 0
        $run.Data.recommended_total_bytes | Should -Be 390
        $state = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:sandbox.StateFile))
        $state.categories | Should -Not -Contain 'browser-chrome'
    }

    It 'leaves out only the app caches of the app that is running' {
        Mock Test-AppRunning { $true } -ParameterFilter { $Names -contains 'slack' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'app-caches'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be 22
        $entry.item_count | Should -Be 1
    }

    It 'skips the Gradle cache while a Gradle daemon is running' {
        Mock Test-AppRunning { $true } -ParameterFilter { $Names -contains 'java' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'gradle-cache').status | Should -Be 'skipped_running'
        (Get-CategoryEntry -Data $run.Data -Id 'cargo-cache').status | Should -Be 'ok'
    }

    It 'measures a tool cache in the directory the tool reports below the default location' {
        $script:reportedDir = Join-Path -Path $script:sandbox.Local -ChildPath 'Yarn\Cache\v6'
        Add-SandboxFile -Path (Join-Path -Path $script:reportedDir -ChildPath 'zqentry') -SizeBytes 44
        Mock Get-ToolPath { 'C:\zqtools\yarn.cmd' } -ParameterFilter { $Name -eq 'yarn' }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @('', $script:reportedDir, '') } } -ParameterFilter {
            $Name -eq 'yarn'
        }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'yarn-cache'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be 44
        $entry.item_count | Should -Be 1
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'reports <Id> as unavailable when <Tool> says its cache is inside Documents' -ForEach @(
        @{ Id = 'npm-cache'; Tool = 'npm' }
        @{ Id = 'yarn-cache'; Tool = 'yarn' }
        @{ Id = 'pnpm-store'; Tool = 'pnpm' }
        @{ Id = 'pip-cache'; Tool = 'pip' }
        @{ Id = 'go-cache'; Tool = 'go' }
    ) {
        $script:toolName = $Tool
        $script:reportedDir = Join-Path -Path $script:sandbox.Home -ChildPath 'Documents'
        Mock Get-ToolPath { 'C:\zqtools\zqtool.exe' } -ParameterFilter { $Name -eq $script:toolName }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:reportedDir) } } -ParameterFilter {
            $Name -eq $script:toolName
        }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id $Id).status | Should -Be 'unavailable'
        $state = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:sandbox.StateFile))
        $state.categories | Should -Not -Contain $Id
        $run.Data.recommended_total_bytes | Should -Be 590
        foreach ($sentinel in $script:sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'reports a tool cache as unavailable when the tool prints something that is not a usable path' {
        Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'pip\Cache\zqwheel') -SizeBytes 17
        Mock Get-ToolPath { 'C:\zqtools\pip.exe' } -ParameterFilter { $Name -eq 'pip' }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @('zqrelative\cache') } } -ParameterFilter {
            $Name -eq 'pip'
        }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'pip-cache').status | Should -Be 'unavailable'
    }

    It 'reports the pnpm store with an unknown size that never counts toward the recommended total' {
        $script:reportedDir = Join-Path -Path $script:sandbox.Local -ChildPath 'pnpm\store\v3'
        Add-SandboxFile -Path (Join-Path -Path $script:reportedDir -ChildPath 'files\zqblob') -SizeBytes 77
        Mock Get-ToolPath { 'C:\zqtools\pnpm.cmd' } -ParameterFilter { $Name -eq 'pnpm' }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:reportedDir) } } -ParameterFilter {
            $Name -eq 'pnpm'
        }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'pnpm-store'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -BeNullOrEmpty
        $entry.item_count | Should -BeNullOrEmpty
        $entry.impact | Should -Match 'known after cleaning'
        $run.Json | Should -Match '"id":"pnpm-store","label":"[^"]*","group":"developer","size_bytes":null,"item_count":null'
        $run.Data.recommended_total_bytes | Should -Be 590
    }

    It 'reports the pnpm store as unavailable when pnpm cannot say where it is' {
        Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'pnpm\store\v3\zqblob') -SizeBytes 77
        Mock Get-ToolPath { 'C:\zqtools\pnpm.cmd' } -ParameterFilter { $Name -eq 'pnpm' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'pnpm-store').status | Should -Be 'unavailable'
    }

    It 'never counts LocalCache of a Store app' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'store-app-caches').size_bytes | Should -Be 25
    }

    It 'skips a Store app that is running' {
        Mock Get-RunningPackageFamilyList { 'zqPackage_abc' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'store-app-caches'
        $entry.status | Should -Be 'skipped_running'
        $entry.size_bytes | Should -Be 0
    }

    It 'leaves out only the Store app that is running' {
        $other = Join-Path -Path $script:sandbox.Local -ChildPath 'Packages\zqOther_def\TempState\zqtemp.bin'
        Add-SandboxFile -Path $other -SizeBytes 9
        Mock Get-RunningPackageFamilyList { 'zqPackage_abc' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'store-app-caches'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be 9
    }

    It 'reports a cache folder relocated behind a junction as unavailable instead of ok' {
        $gradle = Join-Path -Path $script:sandbox.Home -ChildPath '.gradle'
        Move-SandboxFolderBehindJunction -Folder $gradle -NewLocation (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqgradle')

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'gradle-cache').status | Should -Be 'unavailable'
        (Get-CategoryEntry -Data $run.Data -Id 'cargo-cache').status | Should -Be 'ok'
        $state = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:sandbox.StateFile))
        $state.categories | Should -Not -Contain 'gradle-cache'
    }

    It 'falls back to the default cache directory when the tool reports nothing usable' {
        Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'pip\Cache\zqwheel') -SizeBytes 17
        Mock Get-ToolPath { 'C:\zqtools\pip.exe' } -ParameterFilter { $Name -eq 'pip' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'pip-cache'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be 17
    }

    It 'reports an installed tool with no cache as empty' {
        Mock Get-ToolPath { 'C:\zqtools\go.exe' } -ParameterFilter { $Name -eq 'go' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'go-cache').status | Should -Be 'empty'
    }

    It 'reports docker as unavailable when the daemon is down' {
        Mock Get-ToolPath { 'C:\zqtools\docker.exe' } -ParameterFilter { $Name -eq 'docker' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'docker-dangling'
        $entry.status | Should -Be 'unavailable'
        $entry.size_bytes | Should -BeNullOrEmpty
    }

    It 'counts dangling docker images and reports an unknown size as null' {
        Mock Get-ToolPath { 'C:\zqtools\docker.exe' } -ParameterFilter { $Name -eq 'docker' }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @('zqserver') } } -ParameterFilter {
            ($Name -eq 'docker') -and ($Arguments[0] -eq 'info')
        }
        Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @('zqimage1', 'zqimage2') } } -ParameterFilter {
            ($Name -eq 'docker') -and ($Arguments[0] -eq 'images')
        }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'docker-dangling'
        $entry.status | Should -Be 'ok'
        $entry.item_count | Should -Be 2
        $entry.size_bytes | Should -BeNullOrEmpty
        $run.Json | Should -Match '"id":"docker-dangling","label":"[^"]*","group":"developer","size_bytes":null'
        $run.Data.recommended_total_bytes | Should -Be 590
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'reports a filled Recycle Bin as ok, irreversible and not recommended' {
        $script:fakeBin = [pscustomobject]@{ Available = $true; Bytes = [long]900; Items = 3 }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $entry = Get-CategoryEntry -Data $run.Data -Id 'trash'
        $entry.status | Should -Be 'ok'
        $entry.size_bytes | Should -Be 900
        $entry.item_count | Should -Be 3
        $entry.risk | Should -Be 'irreversible'
        $entry.recommended | Should -BeFalse
        $entry.requires_flag | Should -Be '--empty-trash'
    }

    It 'reports the Recycle Bin as unavailable when the shell cannot be queried' {
        $script:fakeBin = [pscustomobject]@{ Available = $false; Bytes = [long]0; Items = 0 }

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'trash').status | Should -Be 'unavailable'
    }

    It 'leaves node-modules-stale out unless --deep is given' {
        $run = Invoke-CleanupJson -Arguments @('scan')

        @($run.Data.categories | Where-Object { $_.id -eq 'node-modules-stale' }).Count | Should -Be 0
    }

    It 'maps an unreadable folder to skipped_no_permission' {
        Mock Measure-Target { [pscustomobject]@{ Bytes = [long]0; Files = 0; Denied = $true } }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
        (Get-CategoryEntry -Data $run.Data -Id 'temp-files').status | Should -Be 'skipped_no_permission'
    }

    It 'survives a category that fails unexpectedly without leaking the error' {
        Mock Measure-Target { throw 'zqboom at C:\zqsecret' }

        $run = Invoke-CleanupJson -Arguments @('scan')

        $run.ExitCode | Should -Be 0
        (Get-CategoryEntry -Data $run.Data -Id 'temp-files').status | Should -Be 'unavailable'
        @($run.Data.categories).Count | Should -Be 20
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'ignores caches reached through a junction' {
        $link = Join-Path -Path $script:sandbox.Local -ChildPath 'Google\Chrome\User Data\Default\Cache\zqlinked'
        Add-SandboxJunction -Link $link -Target (Join-Path -Path $script:sandbox.Home -ChildPath 'Documents')

        $run = Invoke-CleanupJson -Arguments @('scan')

        (Get-CategoryEntry -Data $run.Data -Id 'browser-chrome').size_bytes | Should -Be 200
    }
}
