BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    function Invoke-ScanForToken {
        param([string[]]$Extra = @())
        $run = Invoke-CleanupJson -Arguments ([string[]](@('scan') + $Extra))
        return [string]$run.Data.token
    }

    function Invoke-CleanFor {
        param([string]$Token, [string]$Categories, [string[]]$Extra = @())
        return (Invoke-CleanupJson -Arguments ([string[]](@('clean', '--token', $Token, '--categories', $Categories) + $Extra)))
    }
}

Describe 'clean' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        Add-SandboxCache -Sandbox $script:sandbox
        $script:sentinels = @(Add-SandboxSentinel -Sandbox $script:sandbox)
        $script:chromeBlob = Join-Path -Path $script:sandbox.Local -ChildPath 'Google\Chrome\User Data\Default\Cache\Cache_Data\zqblob1'
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

    Context 'token flow' {
        It 'reports TOKEN_MISSING without a token and deletes nothing' {
            $null = Invoke-ScanForToken

            $run = Invoke-CleanupJson -Arguments @('clean', '--categories', 'browser-chrome')

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'TOKEN_MISSING'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'reports TOKEN_INVALID before any scan' {
            $run = Invoke-CleanFor -Token 'abcdef12' -Categories 'browser-chrome'

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'rejects a wrong token and deletes nothing' {
            $token = Invoke-ScanForToken
            $wrong = '00000000'
            if ($token -eq $wrong) { $wrong = '11111111' }

            $run = Invoke-CleanFor -Token $wrong -Categories 'browser-chrome'

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'expires a token after 15 minutes' {
            $token = Invoke-ScanForToken
            Set-SandboxStateEpoch -StateFile $script:sandbox.StateFile -Replacement ([string]((Get-EpochNow) - 901))

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'TOKEN_EXPIRED'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'accepts a token just inside the 15 minute window' {
            $token = Invoke-ScanForToken
            Set-SandboxStateEpoch -StateFile $script:sandbox.StateFile -Replacement ([string]((Get-EpochNow) - 800))

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.ExitCode | Should -Be 0
            (Get-ResultEntry -Data $run.Data -Id 'browser-chrome').status | Should -Be 'cleaned'
        }

        It 'treats a state file dated in the future as invalid' {
            $token = Invoke-ScanForToken
            Set-SandboxStateEpoch -StateFile $script:sandbox.StateFile -Replacement ([string]((Get-EpochNow) + 5000))

            (Invoke-CleanFor -Token $token -Categories 'browser-chrome').Data.error.code | Should -Be 'TOKEN_INVALID'
        }

        It 'treats a tampered state file as invalid' {
            $token = Invoke-ScanForToken
            Set-SandboxStateEpoch -StateFile $script:sandbox.StateFile -Replacement '"tomorrow"'

            (Invoke-CleanFor -Token $token -Categories 'browser-chrome').Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'treats a corrupt state file as invalid' {
            $token = Invoke-ScanForToken
            [System.IO.File]::WriteAllText($script:sandbox.StateFile, 'zq not json {')

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'makes the token single-use' {
            $token = Invoke-ScanForToken
            $first = Invoke-CleanFor -Token $token -Categories 'browser-chrome'
            Add-SandboxFile -Path $script:chromeBlob

            $second = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $first.ExitCode | Should -Be 0
            Test-Path -LiteralPath $script:sandbox.StateFile | Should -BeFalse
            $second.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'invalidates the previous token when a new scan runs' {
            $first = Invoke-ScanForToken
            $second = Invoke-ScanForToken

            $second | Should -Not -Be $first
            (Invoke-CleanFor -Token $first -Categories 'browser-chrome').Data.error.code | Should -Be 'TOKEN_INVALID'
        }

        It 'rejects a category that was not ok in the scan and keeps the token usable' {
            $token = Invoke-ScanForToken

            $rejected = Invoke-CleanFor -Token $token -Categories 'browser-chrome,browser-firefox'
            $accepted = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $rejected.Data.error.code | Should -Be 'CATEGORY_NOT_IN_SCAN'
            $accepted.ExitCode | Should -Be 0
        }

        It 'deletes nothing when a category is rejected' {
            $token = Invoke-ScanForToken

            $null = Invoke-CleanFor -Token $token -Categories 'browser-chrome,browser-firefox'

            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'requires --empty-trash for the trash category' {
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'trash'

            $run.Data.error.code | Should -Be 'TRASH_FLAG_REQUIRED'
            Should -Invoke Invoke-RecycleBinEmpty -Times 0 -Exactly
        }

        It 'requires a deep scan token for node-modules-stale' {
            Add-SandboxProject -Directory (Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode\zqidle') -IdleDays 100
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'node-modules-stale'

            $run.Data.error.code | Should -Be 'DEEP_SCAN_REQUIRED'
            $modulePath = Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode\zqidle\node_modules\zqpackage\index.js'
            Test-Path -LiteralPath $modulePath | Should -BeTrue
        }

        It 'still enforces the flags when categories are injected into the state file' {
            $token = Invoke-ScanForToken
            $text = [System.IO.File]::ReadAllText($script:sandbox.StateFile)
            $injected = $text.Replace('"categories":[', '"categories":["node-modules-stale",')
            [System.IO.File]::WriteAllText($script:sandbox.StateFile, $injected)

            (Invoke-CleanFor -Token $token -Categories 'trash').Data.error.code | Should -Be 'TRASH_FLAG_REQUIRED'
            (Invoke-CleanFor -Token $token -Categories 'node-modules-stale').Data.error.code | Should -Be 'DEEP_SCAN_REQUIRED'
        }

        It 'does not trust a state file that is a link' {
            $token = Invoke-ScanForToken
            $copy = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqstate-copy'
            [System.IO.File]::Move($script:sandbox.StateFile, $copy)
            try {
                New-Item -ItemType SymbolicLink -Path $script:sandbox.StateFile -Value $copy -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
                return
            }

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $copy | Should -BeTrue
            [System.IO.File]::Delete($script:sandbox.StateFile)
        }
    }

    Context 'deletion' {
        It 'prints one JSON document that matches the schema' {
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.ExitCode | Should -Be 0
            $run.Data.schema_version | Should -Be 1
            $run.Data.command | Should -Be 'clean'
            $run.Data.platform | Should -Be 'windows'
            $run.Data.disk_before.free_bytes | Should -Be 1000000
            $run.Data.disk_after.free_bytes | Should -Be 1000000
            $run.Data.freed_total_bytes | Should -Be 200
            $run.Data.log_file_written | Should -BeFalse
            $run.Data.log_location_hint | Should -BeNullOrEmpty
            $run.Json | Should -Match '"results":\[\{'
            $run.Json | Should -Match '"log_location_hint":null'
            $result = Get-ResultEntry -Data $run.Data -Id 'browser-chrome'
            (@($result.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should -Be 'id,label,freed_bytes,status,error_code'
            $result.freed_bytes | Should -Be 200
            $result.status | Should -Be 'cleaned'
            $result.error_code | Should -BeNullOrEmpty
        }

        It 'cleans every ok category, keeps the category roots and never touches a sentinel' {
            $token = Invoke-ScanForToken
            $all = 'app-caches,temp-files,thumbnail-cache,crash-dumps,store-app-caches,browser-chrome,gradle-cache,cargo-cache'

            $run = Invoke-CleanFor -Token $token -Categories $all

            $run.ExitCode | Should -Be 0
            $run.Data.freed_total_bytes | Should -Be 590
            @($run.Data.results).Count | Should -Be 8
            foreach ($result in $run.Data.results) { $result.status | Should -Be 'cleaned' }
            foreach ($sentinel in $script:sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
            Test-Path -LiteralPath $script:chromeBlob | Should -BeFalse
            $roots = @(
                (Join-Path -Path $script:sandbox.Local -ChildPath 'Google\Chrome\User Data\Default\Cache'),
                (Join-Path -Path $script:sandbox.Local -ChildPath 'Temp'),
                (Join-Path -Path $script:sandbox.Local -ChildPath 'CrashDumps'),
                (Join-Path -Path $script:sandbox.Local -ChildPath 'Packages\zqPackage_abc\TempState'),
                (Join-Path -Path $script:sandbox.Roaming -ChildPath 'Slack\Cache'),
                (Join-Path -Path $script:sandbox.Home -ChildPath '.gradle\caches')
            )
            foreach ($root in $roots) { Test-Path -LiteralPath $root -PathType Container | Should -BeTrue }
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'removes only files older than the age threshold stored by the scan' {
            $token = Invoke-ScanForToken -Extra @('--min-age-days', '45')

            $run = Invoke-CleanFor -Token $token -Categories 'temp-files'

            (Get-ResultEntry -Data $run.Data -Id 'temp-files').freed_bytes | Should -Be 60
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Temp -ChildPath 'zqdir\zqolder.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Temp -ChildPath 'zqold.tmp') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Temp -ChildPath 'zqfresh.tmp') | Should -BeTrue
        }

        It 'skips an app that started after the scan and deletes nothing' {
            $token = Invoke-ScanForToken
            Mock Test-AppRunning { $true } -ParameterFilter { $Names -contains 'chrome' }

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $result = Get-ResultEntry -Data $run.Data -Id 'browser-chrome'
            $result.status | Should -Be 'skipped_running'
            $result.error_code | Should -Be 'APP_RUNNING'
            $result.freed_bytes | Should -Be 0
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'reports a locked file as partial' {
            $token = Invoke-ScanForToken
            $handle = [System.IO.File]::Open($script:chromeBlob, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            try {
                $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'
            } finally {
                $handle.Dispose()
            }

            $result = Get-ResultEntry -Data $run.Data -Id 'browser-chrome'
            $result.status | Should -Be 'partial'
            $result.freed_bytes | Should -Be 100
            $result.error_code | Should -Be 'SOME_ITEMS_REMAIN'
            Test-Path -LiteralPath $script:chromeBlob | Should -BeTrue
        }

        It 'maps a category that fails unexpectedly to failed without leaking the error' {
            $token = Invoke-ScanForToken
            Mock Invoke-GuardedDelete { throw 'zqboom at C:\zqsecret' } -ParameterFilter { $Target.KeepRoot }

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            $run.ExitCode | Should -Be 0
            $result = Get-ResultEntry -Data $run.Data -Id 'browser-chrome'
            $result.status | Should -Be 'failed'
            $result.error_code | Should -Be 'INTERNAL'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'empties the Recycle Bin only with --empty-trash' {
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'trash' -Extra @('--empty-trash')

            $result = Get-ResultEntry -Data $run.Data -Id 'trash'
            $result.status | Should -Be 'cleaned'
            $result.freed_bytes | Should -Be 900
            Should -Invoke Invoke-RecycleBinEmpty -Times 1 -Exactly
        }

        It 'never empties the Recycle Bin for other categories' {
            $token = Invoke-ScanForToken

            $null = Invoke-CleanFor -Token $token -Categories 'browser-chrome' -Extra @('--empty-trash')

            Should -Invoke Invoke-RecycleBinEmpty -Times 0 -Exactly
        }

        It 'cleans a tool cache with the official command and reports the measured difference' {
            $script:npmDir = Join-Path -Path $script:sandbox.Local -ChildPath 'npm-cache'
            $script:npmEntry = Join-Path -Path $script:npmDir -ChildPath '_cacache\zqentry'
            Add-SandboxFile -Path $script:npmEntry -SizeBytes 44
            Mock Get-ToolPath { 'C:\zqtools\npm.cmd' } -ParameterFilter { $Name -eq 'npm' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:npmDir) } } -ParameterFilter {
                ($Name -eq 'npm') -and (($Arguments -join ' ') -eq 'config get cache')
            }
            Mock Invoke-Tool {
                [System.IO.File]::Delete($script:npmEntry)
                [pscustomobject]@{ ExitCode = 0; Output = @() }
            } -ParameterFilter { ($Name -eq 'npm') -and (($Arguments -join ' ') -eq 'cache clean --force') }
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'npm-cache'

            $result = Get-ResultEntry -Data $run.Data -Id 'npm-cache'
            $result.status | Should -Be 'cleaned'
            $result.error_code | Should -BeNullOrEmpty
            $result.freed_bytes | Should -Be 44
            Should -Invoke Invoke-Tool -Times 1 -Exactly -ParameterFilter {
                ($Name -eq 'npm') -and (($Arguments -join ' ') -eq 'cache clean --force')
            }
        }

        It 'never runs <Tool> clean when the tool says its cache is inside Documents' -ForEach @(
            @{ Id = 'npm-cache'; Tool = 'npm'; Default = 'npm-cache'; Entry = 'npm-cache\_cacache\zqentry'; CleanLine = 'cache clean --force' }
            @{ Id = 'yarn-cache'; Tool = 'yarn'; Default = 'Yarn\Cache'; Entry = 'Yarn\Cache\zqentry'; CleanLine = 'cache clean' }
            @{ Id = 'pnpm-store'; Tool = 'pnpm'; Default = 'pnpm\store'; Entry = 'pnpm\store\zqentry'; CleanLine = 'store prune' }
            @{ Id = 'pip-cache'; Tool = 'pip'; Default = 'pip\Cache'; Entry = 'pip\Cache\zqentry'; CleanLine = 'cache purge' }
            @{ Id = 'go-cache'; Tool = 'go'; Default = 'go-build'; Entry = 'go-build\zqentry'; CleanLine = 'clean -cache' }
        ) {
            $script:toolName = $Tool
            $script:cleanLine = $CleanLine
            $script:documents = Join-Path -Path $script:sandbox.Home -ChildPath 'Documents'
            $script:reportedDir = Join-Path -Path $script:sandbox.Local -ChildPath $Default
            $entryFile = Join-Path -Path $script:sandbox.Local -ChildPath $Entry
            Add-SandboxFile -Path $entryFile -SizeBytes 31
            Mock Get-ToolPath { 'C:\zqtools\zqtool.exe' } -ParameterFilter { $Name -eq $script:toolName }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:reportedDir) } } -ParameterFilter {
                $Name -eq $script:toolName
            }
            Mock Invoke-Tool {
                foreach ($file in [System.IO.Directory]::GetFiles($script:documents)) { [System.IO.File]::Delete($file) }
                [pscustomobject]@{ ExitCode = 0; Output = @() }
            } -ParameterFilter { ($Name -eq $script:toolName) -and (($Arguments -join ' ') -eq $script:cleanLine) }
            $token = Invoke-ScanForToken
            $script:reportedDir = $script:documents

            $run = Invoke-CleanFor -Token $token -Categories $Id

            $result = Get-ResultEntry -Data $run.Data -Id $Id
            $result.status | Should -Be 'unavailable'
            $result.error_code | Should -Be 'CUSTOM_LOCATION'
            $result.freed_bytes | Should -Be 0
            Should -Invoke Invoke-Tool -Times 0 -Exactly -ParameterFilter {
                ($Name -eq $script:toolName) -and (($Arguments -join ' ') -eq $script:cleanLine)
            }
            foreach ($sentinel in $script:sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
            Test-Path -LiteralPath $entryFile | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'never runs the tool when its cache was relocated behind a junction' {
            $yarnDir = Join-Path -Path $script:sandbox.Local -ChildPath 'Yarn'
            $script:reportedDir = Join-Path -Path $yarnDir -ChildPath 'Cache'
            Add-SandboxFile -Path (Join-Path -Path $script:reportedDir -ChildPath 'zqentry') -SizeBytes 31
            Mock Get-ToolPath { 'C:\zqtools\yarn.cmd' } -ParameterFilter { $Name -eq 'yarn' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:reportedDir) } } -ParameterFilter {
                $Name -eq 'yarn'
            }
            $token = Invoke-ScanForToken
            $moved = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqyarn'
            Move-SandboxFolderBehindJunction -Folder $yarnDir -NewLocation $moved

            $run = Invoke-CleanFor -Token $token -Categories 'yarn-cache'

            $result = Get-ResultEntry -Data $run.Data -Id 'yarn-cache'
            $result.status | Should -Be 'unavailable'
            $result.error_code | Should -Be 'CUSTOM_LOCATION'
            Should -Invoke Invoke-Tool -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'cache clean' }
            Test-Path -LiteralPath (Join-Path -Path $moved -ChildPath 'Cache\zqentry') | Should -BeTrue
        }

        It 'deletes the default cache directory through the guard when the tool cannot report one' {
            $wheel = Join-Path -Path $script:sandbox.Local -ChildPath 'pip\Cache\zqwheel'
            Add-SandboxFile -Path $wheel -SizeBytes 17
            Mock Get-ToolPath { 'C:\zqtools\pip.exe' } -ParameterFilter { $Name -eq 'pip' }
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'pip-cache'

            $result = Get-ResultEntry -Data $run.Data -Id 'pip-cache'
            $result.status | Should -Be 'cleaned'
            $result.freed_bytes | Should -Be 17
            Test-Path -LiteralPath $wheel | Should -BeFalse
            Should -Invoke Invoke-Tool -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'cache purge' }
            foreach ($sentinel in $script:sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
        }

        It 'reports a failing tool as failed' {
            $script:pipDir = Join-Path -Path $script:sandbox.Local -ChildPath 'pip\Cache'
            Add-SandboxFile -Path (Join-Path -Path $script:pipDir -ChildPath 'zqwheel') -SizeBytes 17
            Mock Get-ToolPath { 'C:\zqtools\pip.exe' } -ParameterFilter { $Name -eq 'pip' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:pipDir) } } -ParameterFilter {
                ($Name -eq 'pip') -and (($Arguments -join ' ') -eq 'cache dir')
            }
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'pip-cache'

            $result = Get-ResultEntry -Data $run.Data -Id 'pip-cache'
            $result.status | Should -Be 'failed'
            $result.error_code | Should -Be 'TOOL_FAILED'
        }

        It 'reports a category that became empty after the scan as not_found' {
            $token = Invoke-ScanForToken
            [System.IO.File]::Delete((Join-Path -Path $script:sandbox.Temp -ChildPath 'zqold.tmp'))
            [System.IO.File]::Delete((Join-Path -Path $script:sandbox.Temp -ChildPath 'zqdir\zqolder.tmp'))
            [System.IO.File]::Delete((Join-Path -Path $script:sandbox.Local -ChildPath 'CrashDumps\zqold.dmp'))
            [System.IO.File]::Delete((Join-Path -Path $script:sandbox.Local -ChildPath 'CrashDumps\zqnew.dmp'))
            $script:fakeBin = [pscustomobject]@{ Available = $true; Bytes = [long]0; Items = 0 }

            $run = Invoke-CleanFor -Token $token -Categories 'temp-files,crash-dumps,trash' -Extra @('--empty-trash')

            foreach ($result in $run.Data.results) {
                $result.status | Should -Be 'not_found'
                $result.error_code | Should -Be 'NOT_FOUND'
                $result.freed_bytes | Should -Be 0
            }
            @($run.Data.results).Count | Should -Be 3
            Should -Invoke Invoke-RecycleBinEmpty -Times 0 -Exactly
        }

        It 'reports a cache folder relocated behind a junction as unavailable and deletes nothing' {
            $token = Invoke-ScanForToken
            $gradle = Join-Path -Path $script:sandbox.Home -ChildPath '.gradle'
            $moved = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqgradle'
            Move-SandboxFolderBehindJunction -Folder $gradle -NewLocation $moved

            $run = Invoke-CleanFor -Token $token -Categories 'gradle-cache'

            $result = Get-ResultEntry -Data $run.Data -Id 'gradle-cache'
            $result.status | Should -Be 'unavailable'
            $result.error_code | Should -Be 'CUSTOM_LOCATION'
            Test-Path -LiteralPath (Join-Path -Path $moved -ChildPath 'caches\zqmodules\zqjar.bin') | Should -BeTrue
        }

        It 'skips a Store app that started after the scan' {
            $token = Invoke-ScanForToken
            Mock Get-RunningPackageFamilyList { 'zqPackage_abc' }

            $run = Invoke-CleanFor -Token $token -Categories 'store-app-caches'

            $result = Get-ResultEntry -Data $run.Data -Id 'store-app-caches'
            $result.status | Should -Be 'skipped_running'
            $result.error_code | Should -Be 'APP_RUNNING'
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Local -ChildPath 'Packages\zqPackage_abc\TempState\zqtemp.bin') | Should -BeTrue
        }

        It 'reports a Store app file that is in use as partial and never touches LocalCache' {
            $token = Invoke-ScanForToken
            $locked = Join-Path -Path $script:sandbox.Local -ChildPath 'Packages\zqPackage_abc\TempState\zqtemp.bin'
            $handle = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            try {
                $run = Invoke-CleanFor -Token $token -Categories 'store-app-caches'
            } finally {
                $handle.Dispose()
            }

            $run.ExitCode | Should -Be 0
            $result = Get-ResultEntry -Data $run.Data -Id 'store-app-caches'
            $result.status | Should -Be 'partial'
            $result.error_code | Should -Be 'SOME_ITEMS_REMAIN'
            $result.freed_bytes | Should -Be 13
            Test-Path -LiteralPath $locked | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.Local -ChildPath 'Packages\zqPackage_abc\LocalCache\zqcache.bin') | Should -BeTrue
        }

        It 'reports docker as unavailable when the daemon stopped after the scan' {
            $script:dockerExit = 0
            Mock Get-ToolPath { 'C:\zqtools\docker.exe' } -ParameterFilter { $Name -eq 'docker' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = $script:dockerExit; Output = @('zqimage1') } } -ParameterFilter {
                $Name -eq 'docker'
            }
            $token = Invoke-ScanForToken
            $script:dockerExit = 1

            $run = Invoke-CleanFor -Token $token -Categories 'docker-dangling'

            $result = Get-ResultEntry -Data $run.Data -Id 'docker-dangling'
            $result.status | Should -Be 'unavailable'
            $result.error_code | Should -Be 'TOOL_UNAVAILABLE'
        }

        It 'prunes only dangling docker images and parses the reclaimed size' {
            Mock Get-ToolPath { 'C:\zqtools\docker.exe' } -ParameterFilter { $Name -eq 'docker' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @('zqimage1') } } -ParameterFilter {
                ($Name -eq 'docker') -and ($Arguments[0] -ne 'image')
            }
            Mock Invoke-Tool {
                [pscustomobject]@{ ExitCode = 0; Output = @('Deleted Images:', 'zqimage1', '', 'Total reclaimed space: 1.5kB') }
            } -ParameterFilter { ($Name -eq 'docker') -and (($Arguments -join ' ') -eq 'image prune --force') }
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'docker-dangling'

            $result = Get-ResultEntry -Data $run.Data -Id 'docker-dangling'
            $result.status | Should -Be 'cleaned'
            $result.freed_bytes | Should -Be 1500
            Should -Invoke Invoke-Tool -Times 0 -Exactly -ParameterFilter {
                ($Name -eq 'docker') -and (($Arguments -contains '-a') -or ($Arguments -contains 'volume') -or ($Arguments -contains 'system'))
            }
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }

    Context 'log' {
        It 'writes no log unless --log is given' {
            $token = Invoke-ScanForToken

            $null = Invoke-CleanFor -Token $token -Categories 'browser-chrome'

            Test-Path -LiteralPath (Join-Path -Path $script:sandbox.StateDir -ChildPath 'logs') | Should -BeFalse
        }

        It 'writes deleted paths to a local log and only a static hint to stdout' {
            $token = Invoke-ScanForToken

            $run = Invoke-CleanFor -Token $token -Categories 'browser-chrome' -Extra @('--log')

            $run.Data.log_file_written | Should -BeTrue
            $run.Data.log_location_hint | Should -BeExactly '%LOCALAPPDATA%\disk-cleanup\logs'
            $logs = @([System.IO.Directory]::GetFiles((Join-Path -Path $script:sandbox.StateDir -ChildPath 'logs')))
            $logs.Count | Should -Be 1
            $lines = @([System.IO.File]::ReadAllLines($logs[0]))
            $lines.Count | Should -Be 4
            ($lines -join '|') | Should -Match 'zqblob1'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }
}
