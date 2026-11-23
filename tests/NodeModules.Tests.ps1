BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    function Get-ModuleFile {
        param([string]$Project)
        return (Join-Path -Path $script:sandbox.Home -ChildPath ($Project + '\node_modules\zqpackage\index.js'))
    }

    function Add-HomeProject {
        param([string]$Project, [int]$IdleDays, [string]$Lockfile = 'package-lock.json', [bool]$WithManifest = $true)
        $directory = Join-Path -Path $script:sandbox.Home -ChildPath $Project
        Add-SandboxProject -Directory $directory -IdleDays $IdleDays -Lockfile $Lockfile -WithManifest $WithManifest
        return $directory
    }

    function Get-DeepEntry {
        param([string[]]$Extra = @())
        $run = Invoke-CleanupJson -Arguments ([string[]](@('scan', '--deep') + $Extra))
        return [pscustomobject]@{ Run = $run; Entry = (Get-CategoryEntry -Data $run.Data -Id 'node-modules-stale') }
    }
}

Describe 'node-modules-stale' {
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

    Context 'scan --deep' {
        It 'appears last with three buckets, is not recommended and needs a rebuild' {
            $deep = Get-DeepEntry

            $deep.Run.ExitCode | Should -Be 0
            @($deep.Run.Data.categories).Count | Should -Be 21
            @($deep.Run.Data.categories)[20].id | Should -Be 'node-modules-stale'
            $deep.Entry.status | Should -Be 'empty'
            $deep.Entry.group | Should -Be 'projects'
            $deep.Entry.risk | Should -Be 'rebuild_needed'
            $deep.Entry.recommended | Should -BeFalse
            (@($deep.Entry.buckets | ForEach-Object { $_.id }) -join ',') | Should -Be '30-90,90-180,180+'
            (@($deep.Entry.buckets | ForEach-Object { $_.min_idle_days }) -join ',') | Should -Be '30,90,180'
            $deep.Run.Json | Should -Match '"buckets":\[\{"id":"30-90","min_idle_days":30,"project_count":0,"size_bytes":0\}'
        }

        It 'sorts idle projects into buckets by idle days' {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 45
            $null = Add-HomeProject -Project 'zqcode\zqbeta' -IdleDays 120
            $null = Add-HomeProject -Project 'zqcode\zqgamma' -IdleDays 400
            $null = Add-HomeProject -Project 'zqwork\zqnested\zqdelta' -IdleDays 500
            $null = Add-HomeProject -Project 'zqcode\zqactive' -IdleDays 10

            $deep = Get-DeepEntry

            $deep.Entry.status | Should -Be 'ok'
            $deep.Entry.item_count | Should -Be 4
            $deep.Entry.size_bytes | Should -Be 400
            $buckets = @($deep.Entry.buckets)
            (@($buckets | ForEach-Object { $_.project_count }) -join ',') | Should -Be '1,1,2'
            (@($buckets | ForEach-Object { $_.size_bytes }) -join ',') | Should -Be '100,100,200'
            $deep.Run.Data.recommended_total_bytes | Should -Be 0
            Assert-PrivateOutput -Json $deep.Run.Json -Sandbox $script:sandbox
        }

        It 'accepts the lockfile <Lockfile>' -ForEach @(
            @{ Lockfile = 'package-lock.json' }
            @{ Lockfile = 'yarn.lock' }
            @{ Lockfile = 'pnpm-lock.yaml' }
            @{ Lockfile = 'bun.lock' }
            @{ Lockfile = 'bun.lockb' }
        ) {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 60 -Lockfile $Lockfile

            (Get-DeepEntry).Entry.item_count | Should -Be 1
        }

        It 'ignores a project without a lockfile' {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 60 -Lockfile ''

            (Get-DeepEntry).Entry.item_count | Should -Be 0
        }

        It 'ignores a project without package.json' {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 60 -WithManifest $false

            (Get-DeepEntry).Entry.item_count | Should -Be 0
        }

        It 'ignores a project with a recently modified file' {
            $directory = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            Add-SandboxFile -Path (Join-Path -Path $directory -ChildPath 'docs\deep\zqnotes.md') -AgeDays 3

            (Get-DeepEntry).Entry.item_count | Should -Be 0
        }

        It 'ignores a project with recent git activity in <Name>' -ForEach @(
            @{ Name = 'index' }
            @{ Name = 'HEAD' }
        ) {
            $directory = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            Add-SandboxFile -Path (Join-Path -Path $directory -ChildPath ('.git\' + $Name)) -AgeDays 2

            (Get-DeepEntry).Entry.item_count | Should -Be 0
        }

        It 'does not count other files inside .git or node_modules as activity' {
            $directory = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            Add-SandboxFile -Path (Join-Path -Path $directory -ChildPath '.git\index') -AgeDays 200
            Add-SandboxFile -Path (Join-Path -Path $directory -ChildPath '.git\objects\zqpack') -AgeDays 1
            Add-SandboxFile -Path (Join-Path -Path $directory -ChildPath 'node_modules\zqfresh\index.js') -AgeDays 1 -SizeBytes 7

            $deep = Get-DeepEntry

            $deep.Entry.item_count | Should -Be 1
            $deep.Entry.size_bytes | Should -Be 107
            @($deep.Entry.buckets)[2].project_count | Should -Be 1
        }

        It 'never counts a project under <Name>' -ForEach @(
            @{ Name = 'a dot-directory'; Project = '.zqhidden\zqalpha' }
            @{ Name = 'AppData'; Project = 'AppData\Local\zqalpha' }
            @{ Name = 'Library'; Project = 'Library\zqalpha' }
            @{ Name = 'another node_modules'; Project = 'zqcode\zqouter\node_modules\zqinner' }
        ) {
            $null = Add-HomeProject -Project $Project -IdleDays 200

            (Get-DeepEntry).Entry.item_count | Should -Be 0
        }

        It 'never counts a node_modules folder that is a junction' {
            $real = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            $linked = Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode\zqlinked'
            Add-SandboxFile -Path (Join-Path -Path $linked -ChildPath 'package.json') -AgeDays 200
            Add-SandboxFile -Path (Join-Path -Path $linked -ChildPath 'yarn.lock') -AgeDays 200
            Add-SandboxJunction -Link (Join-Path -Path $linked -ChildPath 'node_modules') -Target (Join-Path -Path $real -ChildPath 'node_modules')

            (Get-DeepEntry).Entry.item_count | Should -Be 1
        }

        It 'never counts a project that npm link exposes as a global tool' {
            $linked = Add-HomeProject -Project 'zqcode\zqlinkedtool' -IdleDays 200
            $scoped = Add-HomeProject -Project 'zqcode\zqscopedtool' -IdleDays 200
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            $script:globalRoot = Join-Path -Path $script:sandbox.Roaming -ChildPath 'npm\node_modules'
            Add-SandboxFile -Path (Join-Path -Path $script:globalRoot -ChildPath 'zqinstalled\package.json')
            Add-SandboxJunction -Link (Join-Path -Path $script:globalRoot -ChildPath 'zqlinkedtool') -Target $linked
            Add-SandboxJunction -Link (Join-Path -Path $script:globalRoot -ChildPath '@zqscope\zqscopedtool') -Target $scoped
            Mock Get-ToolPath { 'C:\zqtools\npm.cmd' } -ParameterFilter { $Name -eq 'npm' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:globalRoot) } } -ParameterFilter {
                ($Name -eq 'npm') -and (($Arguments -join ' ') -eq 'root -g')
            }

            $deep = Get-DeepEntry

            $deep.Entry.item_count | Should -Be 1
            $deep.Entry.size_bytes | Should -Be 100
            Assert-PrivateOutput -Json $deep.Run.Json -Sandbox $script:sandbox
        }

        It 'keeps the node_modules of an npm linked project when cleaning' {
            $linked = Add-HomeProject -Project 'zqcode\zqlinkedtool' -IdleDays 200
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            $script:globalRoot = Join-Path -Path $script:sandbox.Roaming -ChildPath 'npm\node_modules'
            Add-SandboxJunction -Link (Join-Path -Path $script:globalRoot -ChildPath 'zqlinkedtool') -Target $linked
            Mock Get-ToolPath { 'C:\zqtools\npm.cmd' } -ParameterFilter { $Name -eq 'npm' }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 0; Output = @($script:globalRoot) } } -ParameterFilter {
                ($Name -eq 'npm') -and (($Arguments -join ' ') -eq 'root -g')
            }
            $token = (Get-DeepEntry).Run.Data.token

            $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'node-modules-stale')

            (Get-ResultEntry -Data $run.Data -Id 'node-modules-stale').freed_bytes | Should -Be 100
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqlinkedtool') | Should -BeTrue
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqalpha') | Should -BeFalse
        }

        It 'limits the walk to --projects-dir' {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            $null = Add-HomeProject -Project 'zqother\zqbeta' -IdleDays 200
            $root = Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode'

            (Get-DeepEntry -Extra @('--projects-dir', $root)).Entry.item_count | Should -Be 1
        }

        It 'deletes nothing' {
            $null = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 200
            $before = (Get-SandboxFileList -Root $script:sandbox.Home) -join '|'

            $null = Get-DeepEntry

            $after = @(Get-SandboxFileList -Root $script:sandbox.Home | Where-Object { $_ -ne $script:sandbox.StateFile })
            ($after -join '|') | Should -Be $before
        }
    }

    Context 'clean' {
        BeforeEach {
            $script:alpha = Add-HomeProject -Project 'zqcode\zqalpha' -IdleDays 45
            $script:gamma = Add-HomeProject -Project 'zqcode\zqgamma' -IdleDays 400
            $script:active = Add-HomeProject -Project 'zqcode\zqactive' -IdleDays 5
        }

        It 'removes node_modules of every project idle for 30 days or more by default' {
            $token = (Get-DeepEntry).Run.Data.token

            $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'node-modules-stale')

            $result = Get-ResultEntry -Data $run.Data -Id 'node-modules-stale'
            $result.status | Should -Be 'cleaned'
            $result.freed_bytes | Should -Be 200
            Test-Path -LiteralPath (Join-Path -Path $script:alpha -ChildPath 'node_modules') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path -Path $script:gamma -ChildPath 'node_modules') | Should -BeFalse
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqactive') | Should -BeTrue
            foreach ($project in @($script:alpha, $script:gamma, $script:active)) {
                Test-Path -LiteralPath (Join-Path -Path $project -ChildPath 'package.json') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path -Path $project -ChildPath 'package-lock.json') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path -Path $project -ChildPath 'src\zqsource.js') | Should -BeTrue
            }
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'honours --min-idle-days' {
            $token = (Get-DeepEntry).Run.Data.token
            $line = @('clean', '--token', $token, '--categories', 'node-modules-stale', '--min-idle-days', '100')

            $run = Invoke-CleanupJson -Arguments $line

            (Get-ResultEntry -Data $run.Data -Id 'node-modules-stale').freed_bytes | Should -Be 100
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqalpha') | Should -BeTrue
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqgamma') | Should -BeFalse
        }

        It 'keeps a project that became active after the scan' {
            $token = (Get-DeepEntry).Run.Data.token
            Add-SandboxFile -Path (Join-Path -Path $script:gamma -ChildPath 'src\zqedited.js')

            $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'node-modules-stale')

            (Get-ResultEntry -Data $run.Data -Id 'node-modules-stale').freed_bytes | Should -Be 100
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqgamma') | Should -BeTrue
        }

        It 'removes a junction inside node_modules as a link, leaves its target intact and reports cleaned' {
            $keep = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqshared\zqkeep.js'
            Add-SandboxFile -Path $keep -AgeDays 400
            $link = Join-Path -Path $script:gamma -ChildPath 'node_modules\zqlinked'
            Add-SandboxJunction -Link $link -Target (Split-Path -Path $keep -Parent)
            $token = (Get-DeepEntry).Run.Data.token
            $line = @('clean', '--token', $token, '--categories', 'node-modules-stale', '--min-idle-days', '100')

            $run = Invoke-CleanupJson -Arguments $line

            $result = Get-ResultEntry -Data $run.Data -Id 'node-modules-stale'
            $result.status | Should -Be 'cleaned'
            $result.error_code | Should -BeNullOrEmpty
            $result.freed_bytes | Should -Be 100
            Test-Path -LiteralPath $keep | Should -BeTrue
            [System.IO.Directory]::Exists($link) | Should -BeFalse
            Test-Path -LiteralPath (Join-Path -Path $script:gamma -ChildPath 'node_modules') | Should -BeFalse
        }

        It 'reports partial when a file inside node_modules is in use and the folder remains' {
            $token = (Get-DeepEntry).Run.Data.token
            Add-SandboxFile -Path (Join-Path -Path $script:gamma -ChildPath 'node_modules\zqother\index.js') -AgeDays 400 -SizeBytes 5
            $locked = Get-ModuleFile -Project 'zqcode\zqgamma'
            $line = @('clean', '--token', $token, '--categories', 'node-modules-stale', '--min-idle-days', '100')
            $handle = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            try {
                $run = Invoke-CleanupJson -Arguments $line
            } finally {
                $handle.Dispose()
            }

            $result = Get-ResultEntry -Data $run.Data -Id 'node-modules-stale'
            $result.status | Should -Be 'partial'
            $result.error_code | Should -Be 'SOME_ITEMS_REMAIN'
            Test-Path -LiteralPath $locked | Should -BeTrue
        }

        It 'reports not_found when no project is idle long enough any more' {
            $token = (Get-DeepEntry).Run.Data.token
            Add-SandboxFile -Path (Join-Path -Path $script:alpha -ChildPath 'src\zqedited.js')
            Add-SandboxFile -Path (Join-Path -Path $script:gamma -ChildPath 'src\zqedited.js')

            $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'node-modules-stale')

            $result = Get-ResultEntry -Data $run.Data -Id 'node-modules-stale'
            $result.status | Should -Be 'not_found'
            $result.error_code | Should -Be 'NOT_FOUND'
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqgamma') | Should -BeTrue
        }

        It 'refuses node-modules-stale with a token from a shallow scan' {
            $token = (Invoke-CleanupJson -Arguments @('scan')).Data.token

            $run = Invoke-CleanupJson -Arguments @('clean', '--token', $token, '--categories', 'node-modules-stale')

            $run.Data.error.code | Should -Be 'DEEP_SCAN_REQUIRED'
            Test-Path -LiteralPath (Get-ModuleFile -Project 'zqcode\zqgamma') | Should -BeTrue
        }
    }
}
