BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')
}

Describe 'Test-DeletionAllowed' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:cacheDir = Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\Cache'
        Add-SandboxFile -Path (Join-Path -Path $script:cacheDir -ChildPath 'zqblob.bin')
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'allows a real directory deep inside the user profile' {
        Test-DeletionAllowed -Path $script:cacheDir | Should -BeTrue
    }

    It 'refuses an empty or blank path: "<Value>"' -ForEach @(
        @{ Value = '' }
        @{ Value = '   ' }
    ) {
        Test-DeletionAllowed -Path $Value | Should -BeFalse
    }

    It 'refuses a null path' {
        Test-DeletionAllowed -Path $null | Should -BeFalse
    }

    It 'refuses a relative path: <Value>' -ForEach @(
        @{ Value = 'AppData\Local\Temp' }
        @{ Value = '.\zqapp' }
        @{ Value = '..' }
        @{ Value = '\zqrooted-without-drive' }
        @{ Value = 'C:zqdrive-relative' }
    ) {
        Test-DeletionAllowed -Path $Value | Should -BeFalse
    }

    It 'refuses each allowed root itself' {
        Test-DeletionAllowed -Path $script:sandbox.Home | Should -BeFalse
        Test-DeletionAllowed -Path $script:sandbox.Local | Should -BeFalse
        Test-DeletionAllowed -Path $script:sandbox.Roaming | Should -BeFalse
        Test-DeletionAllowed -Path ($script:sandbox.Home + '\') | Should -BeFalse
    }

    It 'refuses a path less than two levels below the user profile' {
        $documents = Join-Path -Path $script:sandbox.Home -ChildPath 'Documents'
        [void][System.IO.Directory]::CreateDirectory($documents)

        Test-DeletionAllowed -Path $documents | Should -BeFalse
        Test-DeletionAllowed -Path (Join-Path -Path $script:sandbox.Home -ChildPath 'AppData') | Should -BeFalse
    }

    It 'refuses a path outside the user profile' {
        $outsideDir = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqdeep\zqer'
        [void][System.IO.Directory]::CreateDirectory($outsideDir)

        Test-DeletionAllowed -Path $outsideDir | Should -BeFalse
        Test-DeletionAllowed -Path $script:sandbox.Base | Should -BeFalse
        Test-DeletionAllowed -Path 'C:\' | Should -BeFalse
    }

    It 'refuses a path that escapes the user profile through ..' {
        $escaping = $script:cacheDir + '\..\..\..\..\..\..\zqoutside'

        Test-DeletionAllowed -Path $escaping | Should -BeFalse
    }

    It 'refuses a path that does not exist' {
        Test-DeletionAllowed -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\zqmissing') | Should -BeFalse
    }

    It 'refuses a path that contains wildcard characters' {
        Test-DeletionAllowed -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\*') | Should -BeFalse
        Test-DeletionAllowed -Path (Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\Cach?') | Should -BeFalse
    }

    It 'refuses a junction and anything reached through it' {
        $link = Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\zqlink'
        $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqtarget\zqinner'
        Add-SandboxFile -Path (Join-Path -Path $target -ChildPath 'zqkeep.txt')
        Add-SandboxJunction -Link $link -Target (Split-Path -Path $target -Parent)

        Test-DeletionAllowed -Path $link | Should -BeFalse
        Test-DeletionAllowed -Path (Join-Path -Path $link -ChildPath 'zqinner') | Should -BeFalse
    }

    It 'refuses everything when the user profile is not set' {
        $env:USERPROFILE = ''

        Test-DeletionAllowed -Path $script:cacheDir | Should -BeFalse
    }

    It 'treats the path case-insensitively but still requires containment' {
        Test-DeletionAllowed -Path ($script:cacheDir.ToUpperInvariant()) | Should -BeTrue
        Test-DeletionAllowed -Path ($script:sandbox.Home.ToUpperInvariant()) | Should -BeFalse
    }
}

Describe 'Invoke-GuardedDelete' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:cacheDir = Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\Cache'
        Add-SandboxFile -Path (Join-Path -Path $script:cacheDir -ChildPath 'zqold.bin') -AgeDays 30 -SizeBytes 100
        Add-SandboxFile -Path (Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqdeep\zqolder.bin') -AgeDays 60 -SizeBytes 50
        $script:keepFile = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqkeep.txt'
        Add-SandboxFile -Path $script:keepFile -AgeDays 90
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'deletes the contents and keeps the root directory' {
        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $null

        $outcome.Refused | Should -BeFalse
        $outcome.FailedCount | Should -Be 0
        $outcome.DeletedFiles | Should -Be 2
        $outcome.FreedBytes | Should -Be 150
        Test-Path -LiteralPath $script:cacheDir -PathType Container | Should -BeTrue
        @([System.IO.Directory]::GetFileSystemEntries($script:cacheDir)).Count | Should -Be 0
    }

    It 'measures exactly what it would delete' {
        $measure = Measure-Target -Target (Get-CleanTarget -Path $script:cacheDir)

        $measure.Bytes | Should -Be 150
        $measure.Files | Should -Be 2
        $measure.Denied | Should -BeFalse
    }

    It 'refuses <Name> and deletes nothing' -ForEach @(
        @{ Name = 'an empty path'; Kind = 'empty' }
        @{ Name = 'a relative path'; Kind = 'relative' }
        @{ Name = 'the user profile root'; Kind = 'home' }
        @{ Name = 'the local app data root'; Kind = 'local' }
        @{ Name = 'a directory outside the user profile'; Kind = 'outside' }
    ) {
        $paths = @{
            empty    = ''
            relative = 'AppData\Local\zqapp\Cache'
            home     = $script:sandbox.Home
            local    = $script:sandbox.Local
            outside  = $script:sandbox.Outside
        }
        $before = (Get-SandboxFileList -Root $script:sandbox.Base) -join '|'

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $paths[$Kind]) -Sink $null

        $outcome.Refused | Should -BeTrue
        $outcome.DeletedFiles | Should -Be 0
        ((Get-SandboxFileList -Root $script:sandbox.Base) -join '|') | Should -Be $before
    }

    It 'refuses a target that is itself a junction' {
        $link = Join-Path -Path $script:sandbox.Local -ChildPath 'zqapp\zqlinked'
        Add-SandboxJunction -Link $link -Target $script:sandbox.Outside

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $link) -Sink $null

        $outcome.Refused | Should -BeTrue
        Test-Path -LiteralPath $script:keepFile | Should -BeTrue
    }

    It 'never follows a junction inside the tree that points outside' {
        $link = Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqescape'
        Add-SandboxJunction -Link $link -Target $script:sandbox.Outside

        $measure = Measure-Target -Target (Get-CleanTarget -Path $script:cacheDir)
        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $null

        $measure.Files | Should -Be 2
        $outcome.DeletedFiles | Should -Be 2
        $outcome.FreedBytes | Should -Be 150
        $outcome.FailedCount | Should -Be 0
        Test-Path -LiteralPath $script:keepFile | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:cacheDir -ChildPath 'zqold.bin') | Should -BeFalse
    }

    It 'removes a junction inside the tree as a link and leaves its target intact' {
        $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqshared'
        $kept = Join-Path -Path $target -ChildPath 'zqinner\zqkept.bin'
        Add-SandboxFile -Path $kept -AgeDays 90
        $link = Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqescape'
        Add-SandboxJunction -Link $link -Target $target
        $sink = New-Object -TypeName 'System.Collections.Generic.List[string]'

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $sink

        $outcome.FailedCount | Should -Be 0
        [System.IO.Directory]::Exists($link) | Should -BeFalse
        Test-Path -LiteralPath $kept | Should -BeTrue
        Test-Path -LiteralPath $script:keepFile | Should -BeTrue
        @([System.IO.Directory]::GetFileSystemEntries($script:cacheDir)).Count | Should -Be 0
        $sink.Count | Should -Be 3
    }

    It 'keeps a junction that is newer than the cutoff' {
        $link = Join-Path -Path $script:cacheDir -ChildPath 'zqfreshlink'
        Add-SandboxJunction -Link $link -Target $script:sandbox.Outside
        $cutoff = [System.DateTime]::UtcNow.AddDays(-7)

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir -Cutoff $cutoff) -Sink $null

        $outcome.DeletedFiles | Should -Be 2
        [System.IO.Directory]::Exists($link) | Should -BeTrue
        Test-Path -LiteralPath $script:keepFile | Should -BeTrue
    }

    It 'counts a directory that could not be emptied as a failure' {
        $locked = Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqdeep\zqolder.bin'
        $handle = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir -KeepRoot $false) -Sink $null
        } finally {
            $handle.Dispose()
        }

        $outcome.DeletedFiles | Should -Be 1
        $outcome.FailedCount | Should -BeGreaterThan 1
        Test-Path -LiteralPath $script:cacheDir -PathType Container | Should -BeTrue
    }

    It 'never follows a file symlink that points outside' {
        $link = Join-Path -Path $script:cacheDir -ChildPath 'zqfilelink.txt'
        try {
            New-Item -ItemType SymbolicLink -Path $link -Value $script:keepFile -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
            return
        }

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $null

        $outcome.DeletedFiles | Should -Be 2
        Test-Path -LiteralPath $script:keepFile | Should -BeTrue
        [System.IO.File]::Delete($link)
    }

    It 'keeps files newer than the cutoff and the directories that hold them' {
        $fresh = Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqfresh.bin'
        Add-SandboxFile -Path $fresh -AgeDays 1
        $cutoff = [System.DateTime]::UtcNow.AddDays(-7)

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir -Cutoff $cutoff) -Sink $null

        $outcome.DeletedFiles | Should -Be 2
        Test-Path -LiteralPath $fresh | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $script:cacheDir -ChildPath 'zqold.bin') | Should -BeFalse
    }

    It 'deletes read-only files' {
        $readOnly = Join-Path -Path $script:cacheDir -ChildPath 'zqreadonly.bin'
        Add-SandboxFile -Path $readOnly -AgeDays 10
        [System.IO.File]::SetAttributes($readOnly, [System.IO.FileAttributes]::ReadOnly)

        $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $null

        $outcome.FailedCount | Should -Be 0
        Test-Path -LiteralPath $readOnly | Should -BeFalse
    }

    It 'resets a file that is only read-only to normal attributes before deleting it' {
        $readOnly = Join-Path -Path $script:cacheDir -ChildPath 'zqreadonly.bin'
        Add-SandboxFile -Path $readOnly -AgeDays 10
        [System.IO.File]::SetAttributes($readOnly, [System.IO.FileAttributes]::ReadOnly)
        $info = New-Object -TypeName System.IO.FileInfo -ArgumentList $readOnly

        Invoke-EntryDelete -Info $info | Should -BeTrue

        Test-Path -LiteralPath $readOnly | Should -BeFalse
    }

    It 'reports a locked file as a failure instead of throwing' {
        $locked = Join-Path -Path $script:cacheDir -ChildPath 'zqold.bin'
        $handle = [System.IO.File]::Open($locked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $outcome = Invoke-GuardedDelete -Target (Get-CleanTarget -Path $script:cacheDir) -Sink $null
        } finally {
            $handle.Dispose()
        }

        $outcome.FailedCount | Should -BeGreaterThan 0
        $outcome.DeletedFiles | Should -Be 1
        Test-Path -LiteralPath $locked | Should -BeTrue
    }

    It 'skips excluded top-level names' {
        $target = Get-CleanTarget -Path $script:cacheDir -ExcludeNames @('zqsub')

        $outcome = Invoke-GuardedDelete -Target $target -Sink $null

        $outcome.DeletedFiles | Should -Be 1
        Test-Path -LiteralPath (Join-Path -Path $script:cacheDir -ChildPath 'zqsub\zqdeep\zqolder.bin') | Should -BeTrue
    }

    It 'limits deletion to top-level files that match the patterns' {
        Add-SandboxFile -Path (Join-Path -Path $script:cacheDir -ChildPath 'thumbcache_96.db') -SizeBytes 10
        $target = Get-CleanTarget -Path $script:cacheDir -FilePatterns @('thumbcache_*.db')

        $outcome = Invoke-GuardedDelete -Target $target -Sink $null

        $outcome.DeletedFiles | Should -Be 1
        $outcome.FreedBytes | Should -Be 10
        Test-Path -LiteralPath (Join-Path -Path $script:cacheDir -ChildPath 'zqold.bin') | Should -BeTrue
    }

    It 'removes the root too when asked, and records deleted paths in the sink' {
        $sink = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $target = Get-CleanTarget -Path $script:cacheDir -KeepRoot $false

        $outcome = Invoke-GuardedDelete -Target $target -Sink $sink

        $outcome.DeletedFiles | Should -Be 2
        Test-Path -LiteralPath $script:cacheDir | Should -BeFalse
        $sink.Count | Should -Be 2
    }
}
