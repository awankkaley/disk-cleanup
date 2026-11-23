BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    $script:applyFields = @(
        'schema_version', 'command', 'platform', 'selected_count', 'trashed_count', 'trashed_bytes',
        'skipped_changed_count', 'skipped_no_permission_count', 'failed_count', 'ignored_count', 'disk_before',
        'disk_after', 'space_freed_when_trash_emptied'
    )
    $script:countFields = @(
        'trashed_count', 'skipped_changed_count', 'skipped_no_permission_count', 'failed_count', 'ignored_count'
    )

    function Invoke-Apply {
        param([string]$Token)
        return (Invoke-CleanupJson -Arguments @('review-apply', '--token', $Token))
    }

    function Get-RecycledNameList {
        param($Sandbox)
        return @([System.IO.Directory]::GetFiles($Sandbox.Recycle) | ForEach-Object {
                [System.IO.Path]::GetFileName($_).Substring(33)
            } | Sort-Object)
    }

    function Add-RawSelection {
        param($Sandbox, [string]$Content, [string]$Name = 'disk-cleanup-selection.json')
        $path = Join-Path -Path $Sandbox.Downloads -ChildPath $Name
        [System.IO.File]::WriteAllText($path, $Content, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        return $path
    }
}

Describe 'review-apply' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:files = Add-SandboxReviewFixture -Sandbox $script:sandbox
        $script:recycleDir = $script:sandbox.Recycle
        Mock Get-AccountProfilePath { $null }
        Mock Get-DiskInfo { [pscustomobject]@{ TotalBytes = [long]2000000; FreeBytes = [long]1000000 } }
        Mock Open-ReviewReport { $true }
        Mock Get-AllocatedFileSize { $null }
        Mock Test-RecycleBinCanHold { $true }
        # Stands in for the Recycle Bin: the file is moved into a sandbox folder, so a
        # test can prove it was moved there and not destroyed.
        Mock Send-FileToRecycleBin {
            $name = [System.Guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($Path)
            [System.IO.File]::Move($Path, [System.IO.Path]::Combine($script:recycleDir, $name))
            'trashed'
        }
        $script:token = Invoke-ReviewForToken
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    Context 'moving the ticked files' {
        It 'moves only the ticked items, into the Recycle Bin, and prints one matching JSON document' {
            $selection = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2, 4)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            @($run.Json -split "`n").Count | Should -Be 1
            (@($run.Data.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should -Be ($script:applyFields -join ',')
            $run.Data.command | Should -Be 'review-apply'
            $run.Data.platform | Should -Be 'windows'
            $run.Data.selected_count | Should -Be 2
            $run.Data.trashed_count | Should -Be 2
            $run.Data.trashed_bytes | Should -Be 11534636
            $run.Data.skipped_changed_count | Should -Be 0
            $run.Data.skipped_no_permission_count | Should -Be 0
            $run.Data.failed_count | Should -Be 0
            $run.Data.ignored_count | Should -Be 0
            $run.Data.disk_before.free_bytes | Should -Be 1000000
            $run.Data.disk_after.free_bytes | Should -Be 1000000
            $run.Data.space_freed_when_trash_emptied | Should -BeTrue
            $run.Json | Should -Match '"trashed_bytes":11534636[,}]'
            Test-Path -LiteralPath $script:files.Archive | Should -BeFalse
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeFalse
            ((Get-RecycledNameList -Sandbox $script:sandbox) -join ',') | Should -Be 'zqarchive.zip,zqold-installer.exe'
            Test-Path -LiteralPath $selection | Should -BeFalse
        }

        It 'keeps the recycled file whole' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $null = Invoke-Apply -Token $script:token

            $recycled = @([System.IO.Directory]::GetFiles($script:sandbox.Recycle))
            $recycled.Count | Should -Be 1
            (New-Object -TypeName System.IO.FileInfo -ArgumentList $recycled[0]).Length | Should -Be 12582912
        }

        It 'leaves every file that was not ticked exactly where it was' {
            $sentinels = @(Add-SandboxSentinel -Sandbox $script:sandbox)
            $script:token = Invoke-ReviewForToken
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(3)
            $before = @(Get-SandboxFileList -Root $script:sandbox.Home)

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            $gone = @($before | Where-Object { -not [System.IO.File]::Exists($_) } | ForEach-Object { [System.IO.Path]::GetFileName($_) })
            $gone.Count | Should -Be 4
            foreach ($name in @('disk-cleanup-selection.json', 'review-manifest', 'review.html', 'zqbig-old.iso')) {
                $gone | Should -Contain $name
            }
            foreach ($sentinel in $sentinels) { Test-Path -LiteralPath $sentinel | Should -BeTrue }
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
        }

        It 'keeps file names, paths and user names out of stdout' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 2, 3, 4, 5, 77)

            $run = Invoke-Apply -Token $script:token

            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
            foreach ($word in @('holiday', 'archive', 'installer', 'Videos', 'Downloads', 'Documents')) {
                $run.Json | Should -Not -Match $word
            }
        }

        It 'ignores ids that are not in the manifest and counts them' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5, 6, 900, 0)

            $run = Invoke-Apply -Token $script:token

            $run.Data.selected_count | Should -Be 4
            $run.Data.trashed_count | Should -Be 1
            $run.Data.ignored_count | Should -Be 3
            Test-Path -LiteralPath $script:files.OldNotes | Should -BeFalse
            Test-Path -LiteralPath $script:files.Recent | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
        }

        It 'counts a repeated id once' {
            $secret = Get-SandboxSecret -Manifest $script:sandbox.Manifest
            $null = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","secret":"' + $secret + '","ids":[4,4,04,4]}')

            $run = Invoke-Apply -Token $script:token

            $run.Data.selected_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 1
        }

        It 'accepts an empty selection and moves nothing' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @()

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.selected_count | Should -Be 0
            $run.Data.trashed_count | Should -Be 0
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeFalse
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeFalse
        }

        It 'moves a file whose name is full of shell and wildcard characters, and not its look-alikes' {
            $videos = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos'
            $odd = Join-Path -Path $videos -ChildPath 'zq[ab]$(calc)`&''%TEMP%;{1}.bin'
            Add-SandboxBigFile -Path $odd -SizeMb 20
            Add-SandboxBigFile -Path (Join-Path -Path $videos -ChildPath 'zqa$(calc)`&''%TEMP%;{1}.bin') -SizeMb 19
            Add-SandboxBigFile -Path (Join-Path -Path $videos -ChildPath 'zqb$(calc)`&''%TEMP%;{1}.bin') -SizeMb 18
            $script:token = Invoke-ReviewForToken
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            $run.Data.trashed_bytes | Should -Be 20971520
            [System.IO.File]::Exists($odd) | Should -BeFalse
            @([System.IO.Directory]::GetFiles($videos)).Count | Should -Be 3
            @([System.IO.Directory]::GetFiles($script:sandbox.Recycle)).Count | Should -Be 1
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'always accounts for every selected id' {
            [System.IO.File]::SetLastWriteTimeUtc($script:files.Archive, [System.DateTime]::UtcNow)
            Mock Test-RecycleBinCanHold { $false } -ParameterFilter { $Path -like '*zqbig-old.iso' }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 2, 3, 4, 5, 6, 7)

            $run = Invoke-Apply -Token $script:token

            $sum = 0
            foreach ($field in $script:countFields) { $sum += [int]$run.Data.$field }
            $sum | Should -Be $run.Data.selected_count
            $run.Data.selected_count | Should -Be 7
            $run.Data.trashed_count | Should -Be 3
            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.failed_count | Should -Be 1
            $run.Data.ignored_count | Should -Be 2
        }
    }

    Context 'files that changed after the review' {
        It 'skips a file whose <Name> changed' -ForEach @(
            @{ Name = 'size'; Kind = 'size' }
            @{ Name = 'modification time'; Kind = 'time' }
            @{ Name = 'content and time'; Kind = 'rewrite' }
        ) {
            if ($Kind -eq 'size') {
                $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:files.OldInstaller)
                Add-SandboxFile -Path $script:files.OldInstaller -SizeBytes 301
                [System.IO.File]::SetLastWriteTimeUtc($script:files.OldInstaller, $stamp)
            }
            if ($Kind -eq 'time') { [System.IO.File]::SetLastWriteTimeUtc($script:files.OldInstaller, [System.DateTime]::UtcNow.AddDays(-199)) }
            if ($Kind -eq 'rewrite') { Add-SandboxFile -Path $script:files.OldInstaller -SizeBytes 300 }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4, 5)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldNotes | Should -BeFalse
        }

        It 'skips a file that is gone' {
            [System.IO.File]::Move($script:files.Archive, (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmoved-away.zip'))
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 0
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }

        It 'skips a file that was swapped for a symbolic link' {
            $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqprecious.zip'
            [System.IO.File]::Move($script:files.Archive, $target)
            try {
                New-Item -ItemType SymbolicLink -Path $script:files.Archive -Value $target -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
                return
            }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 0
            Test-Path -LiteralPath $target | Should -BeTrue
            (New-Object -TypeName System.IO.FileInfo -ArgumentList $target).Length | Should -Be 11534336
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            [System.IO.File]::Delete($script:files.Archive)
        }

        It 'skips a file that was swapped for a junction' {
            $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqprecious-folder'
            Add-SandboxFile -Path (Join-Path -Path $target -ChildPath 'zqkeep.txt')
            [System.IO.File]::Move($script:files.Archive, (Join-Path -Path $target -ChildPath 'zqarchive.zip'))
            Add-SandboxJunction -Link $script:files.Archive -Target $target
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            Test-Path -LiteralPath (Join-Path -Path $target -ChildPath 'zqkeep.txt') | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }

        It 'skips a file whose folder was swapped for a junction, even though size and time still match' {
            $videos = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos'
            $moved = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmoved-videos'
            Move-SandboxFolderBehindJunction -Folder $videos -NewLocation $moved
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 5)

            $run = Invoke-Apply -Token $script:token

            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath (Join-Path -Path $moved -ChildPath 'zqholiday.mp4') | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
        }

        It 'skips a file that became <Name> after the review' -ForEach @(
            @{ Name = 'a cloud-only placeholder'; Attribute = 'Offline' }
            @{ Name = 'hidden'; Attribute = 'Hidden' }
        ) {
            if (-not (Test-WindowsHost)) {
                Set-ItResult -Skipped -Because 'file attributes only exist on Windows'
                return
            }
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($script:files.Holiday)
            [System.IO.File]::SetAttributes($script:files.Holiday, [System.IO.FileAttributes]$Attribute)
            [System.IO.File]::SetLastWriteTimeUtc($script:files.Holiday, $stamp)
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }
    }

    Context 'a tampered manifest' {
        It 'refuses a path that was edited to point <Name>' -ForEach @(
            @{ Name = 'outside the user profile'; Kind = 'outside' }
            @{ Name = 'into AppData'; Kind = 'appdata' }
            @{ Name = 'into a dot-directory'; Kind = 'dot' }
            @{ Name = 'into a bundle'; Kind = 'bundle' }
            @{ Name = 'into node_modules'; Kind = 'modules' }
            @{ Name = 'at the state directory'; Kind = 'state' }
        ) {
            $victim = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqvictim.bin'
            if ($Kind -eq 'appdata') { $victim = Join-Path -Path $script:sandbox.Roaming -ChildPath 'zqapp\zqsettings.db' }
            if ($Kind -eq 'dot') { $victim = Join-Path -Path $script:sandbox.Home -ChildPath '.ssh\zqid_rsa' }
            if ($Kind -eq 'bundle') { $victim = Join-Path -Path $script:sandbox.Home -ChildPath 'Pictures\zqFamily.photoslibrary\zqoriginal.bin' }
            if ($Kind -eq 'modules') { $victim = Join-Path -Path $script:sandbox.Home -ChildPath 'zqcode\node_modules\zqpackage\zqindex.js' }
            if ($Kind -eq 'state') { $victim = $script:sandbox.Report }
            if ($Kind -ne 'state') { Add-SandboxFile -Path $victim -SizeBytes 64 -AgeDays 10 }
            Set-SandboxManifestPath -Manifest $script:sandbox.Manifest -Id 1 -Path (Get-NormalizedPath -Path $victim)
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 4)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 1
            if ($Kind -ne 'state') { Test-Path -LiteralPath $victim | Should -BeTrue }
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'refuses a path that is spelled differently from what Windows stores: <Name>' -ForEach @(
            @{ Name = 'dot-dot segments'; Kind = 'dots' }
            @{ Name = 'other letter case'; Kind = 'case' }
            @{ Name = 'a wildcard'; Kind = 'wildcard' }
            @{ Name = 'a relative path'; Kind = 'relative' }
        ) {
            $real = Get-NormalizedPath -Path $script:files.Archive
            $variant = [System.IO.Path]::GetDirectoryName($real) + '\..\Documents\zqarchive.zip'
            if ($Kind -eq 'case') { $variant = $real.ToUpperInvariant() }
            if ($Kind -eq 'wildcard') { $variant = [System.IO.Path]::GetDirectoryName($real) + '\zqarch*.zip' }
            if ($Kind -eq 'relative') { $variant = 'Documents\zqarchive.zip' }
            $text = [System.IO.File]::ReadAllText($script:sandbox.Manifest)
            [System.IO.File]::WriteAllText($script:sandbox.Manifest, $text.Replace($real, $variant))
            Update-SandboxManifestDigest -Manifest $script:sandbox.Manifest
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 0
            Test-Path -LiteralPath $script:files.Archive | Should -BeTrue
        }

        It 'treats a manifest with <Name> as an invalid token and moves nothing' -ForEach @(
            @{ Name = 'a malformed line'; Kind = 'garbage' }
            @{ Name = 'an unknown group'; Kind = 'group' }
            @{ Name = 'a repeated id'; Kind = 'repeat' }
            @{ Name = 'a negative size'; Kind = 'negative' }
            @{ Name = 'another header'; Kind = 'header' }
            @{ Name = 'no content'; Kind = 'empty' }
            @{ Name = 'no secret line'; Kind = 'secret' }
            @{ Name = 'no digest line'; Kind = 'digest' }
            @{ Name = 'a size threshold below the minimum'; Kind = 'threshold' }
            @{ Name = 'an age threshold below the minimum'; Kind = 'age' }
        ) {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 2, 3, 4, 5)
            $text = [System.IO.File]::ReadAllText($script:sandbox.Manifest)
            $changed = $text + 'zqgarbage $(calc)' + [char]10
            if ($Kind -eq 'group') { $changed = $text.Replace('old-downloads', 'everything') }
            if ($Kind -eq 'repeat') { $changed = $text + ($text -split [char]10)[7] + [char]10 }
            if ($Kind -eq 'secret') { $changed = [regex]::Replace($text, '(?m)^secret [0-9a-f]{32}\n', '') }
            if ($Kind -eq 'digest') { $changed = [regex]::Replace($text, '(?m)^sha256 [0-9a-f]{64}\n', '') }
            if ($Kind -eq 'threshold') { $changed = $text.Replace('min-size-mb 10', 'min-size-mb 9') }
            if ($Kind -eq 'age') { $changed = $text.Replace('downloads-age-days 90', 'downloads-age-days 6') }
            if ($Kind -eq 'negative') { $changed = $text.Replace(([string][char]9 + '300' + [char]9 + '300' + [char]9), ([string][char]9 + '-300' + [char]9 + '300' + [char]9)) }
            if ($Kind -eq 'header') { $changed = $text.Replace('disk-cleanup-review-manifest 1', 'disk-cleanup-review-manifest 2') }
            if ($Kind -eq 'empty') { $changed = '' }
            $changed | Should -Not -BeExactly $text
            [System.IO.File]::WriteAllText($script:sandbox.Manifest, $changed)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'rejects a manifest in which <Name> without a matching digest, and moves nothing' -ForEach @(
            @{ Name = 'a line was added'; Kind = 'added' }
            @{ Name = 'a line was removed'; Kind = 'removed' }
            @{ Name = 'a path was edited'; Kind = 'path' }
            @{ Name = 'a size was edited'; Kind = 'size' }
            @{ Name = 'the size threshold was edited'; Kind = 'threshold' }
            @{ Name = 'the age threshold was edited'; Kind = 'age' }
            @{ Name = 'the digest was edited'; Kind = 'digest' }
        ) {
            $selection = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 2, 3, 4, 5, 6)
            $tab = [string][char]9
            $small = New-Object -TypeName System.IO.FileInfo -ArgumentList (Get-NormalizedPath -Path $script:files.Small)
            $text = [System.IO.File]::ReadAllText($script:sandbox.Manifest)
            $changed = $text + (@('6', '50', '50', [string]$small.LastWriteTimeUtc.Ticks, 'large-files', $small.FullName) -join $tab) + [char]10
            if ($Kind -eq 'removed') { $changed = $text.Substring(0, $text.TrimEnd([char]10).LastIndexOf([char]10) + 1) }
            if ($Kind -eq 'path') { $changed = $text.Replace('zqholiday.mp4', 'zqsmall.txt') }
            if ($Kind -eq 'size') { $changed = $text.Replace(($tab + '300' + $tab + '300' + $tab), ($tab + '301' + $tab + '300' + $tab)) }
            if ($Kind -eq 'threshold') { $changed = $text.Replace('min-size-mb 10', 'min-size-mb 11') }
            if ($Kind -eq 'age') { $changed = $text.Replace('downloads-age-days 90', 'downloads-age-days 91') }
            if ($Kind -eq 'digest') { $changed = [regex]::Replace($text, '(?m)^sha256 [0-9a-f]{64}$', ('sha256 ' + ('0' * 64))) }
            $changed | Should -Not -BeExactly $text
            [System.IO.File]::WriteAllText($script:sandbox.Manifest, $changed)
            $before = @(Get-SandboxFileList -Root $script:sandbox.Home) -join '|'

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            (@(Get-SandboxFileList -Root $script:sandbox.Home) -join '|') | Should -Be $before
            Test-Path -LiteralPath $selection | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'refuses a genuine-looking line that was added for <Name>, even with a matching digest' -ForEach @(
            @{ Name = 'a small file as a large file'; Group = 'large-files'; Target = 'Small' }
            @{ Name = 'a file outside Downloads as an old download'; Group = 'old-downloads'; Target = 'Small' }
            @{ Name = 'a recent download as an old download'; Group = 'old-downloads'; Target = 'Recent' }
            @{ Name = 'a file in a Downloads subfolder as an old download'; Group = 'old-downloads'; Target = 'Nested' }
        ) {
            $victim = Get-NormalizedPath -Path ([string]$script:files.$Target)
            Add-SandboxManifestItem -Manifest $script:sandbox.Manifest -Id 6 -Group $Group -Path $victim
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(6, 4)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.selected_count | Should -Be 2
            $run.Data.skipped_changed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $victim | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeFalse
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
        }

        It 'applies the thresholds stored by the review, not the defaults' {
            $script:token = Invoke-ReviewForToken -Extra @('--downloads-age-days', '150')
            $text = [System.IO.File]::ReadAllText($script:sandbox.Manifest)
            $text | Should -Match '(?m)^min-size-mb 10$'
            $text | Should -Match '(?m)^downloads-age-days 150$'
            Add-SandboxManifestItem -Manifest $script:sandbox.Manifest -Id 6 -Group 'old-downloads' -Path (Get-NormalizedPath -Path $script:files.OldNotes)
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4, 6)

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            $run.Data.skipped_changed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.OldNotes | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeFalse
        }

        It 'does not trust a manifest that is a link' {
            $copy = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmanifest-copy'
            [System.IO.File]::Move($script:sandbox.Manifest, $copy)
            try {
                New-Item -ItemType SymbolicLink -Path $script:sandbox.Manifest -Value $copy -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
                return
            }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $copy | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            [System.IO.File]::Delete($script:sandbox.Manifest)
        }
    }

    Context 'the Recycle Bin' {
        It 'leaves a file in place when the Recycle Bin cannot hold it, because Windows would destroy it' {
            Mock Test-RecycleBinCanHold { $false }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1, 4)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.failed_count | Should -Be 2
            $run.Data.trashed_count | Should -Be 0
            $run.Data.trashed_bytes | Should -Be 0
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }

        It 'asks whether the bin can hold the full length of the file' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $null = Invoke-Apply -Token $script:token

            Should -Invoke Test-RecycleBinCanHold -Times 1 -Exactly -ParameterFilter { ($Bytes -eq 12582912) -and ($Path -like '*zqholiday.mp4') }
        }

        It 'counts <Result> from the Recycle Bin as <Field> and keeps the file' -ForEach @(
            @{ Result = 'denied'; Field = 'skipped_no_permission_count' }
            @{ Result = 'failed'; Field = 'failed_count' }
            @{ Result = 'zqsomething-else'; Field = 'failed_count' }
            @{ Result = ''; Field = 'failed_count' }
        ) {
            $script:recycleResult = $Result
            Mock Send-FileToRecycleBin { $script:recycleResult }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.$Field | Should -Be 1
            $run.Data.trashed_count | Should -Be 0
            $run.Data.trashed_bytes | Should -Be 0
            Test-Path -LiteralPath $script:files.Archive | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'does not count a file as recycled when it is still there afterwards' {
            Mock Send-FileToRecycleBin { 'trashed' }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)

            $run = Invoke-Apply -Token $script:token

            $run.Data.failed_count | Should -Be 1
            $run.Data.trashed_count | Should -Be 0
        }

        It 'reports a failure, not a crash, when the Recycle Bin throws' {
            Mock Send-FileToRecycleBin { throw 'zqboom at C:\zqsecret\zqarchive.zip' }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2, 4)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.failed_count | Should -Be 2
            Test-Path -LiteralPath $script:files.Archive | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }
}
