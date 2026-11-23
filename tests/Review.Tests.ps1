BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    $script:largeBytes = [long]34603008
    $script:reviewFields = @(
        'schema_version', 'command', 'platform', 'token', 'token_expires_in_seconds', 'groups', 'total_item_count',
        'total_size_bytes', 'truncated', 'report_opened', 'report_location_hint', 'selection_file_hint',
        'downloads_readable'
    )

    function Invoke-Review {
        param([string[]]$Extra = @())
        return (Invoke-CleanupJson -Arguments ([string[]](@('review', '--min-size-mb', '10') + $Extra)))
    }

    function Get-ReviewGroup {
        param($Data, [string]$Id)
        return @($Data.groups | Where-Object { $_.id -eq $Id })[0]
    }

    function Get-ManifestLeafList {
        param([string]$Manifest)
        return @(Get-SandboxManifestPathList -Manifest $Manifest | ForEach-Object { [System.IO.Path]::GetFileName($_) })
    }
}

Describe 'review' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:files = Add-SandboxReviewFixture -Sandbox $script:sandbox
        Mock Get-AccountProfilePath { $null }
        Mock Get-DiskInfo { [pscustomobject]@{ TotalBytes = [long]2000000; FreeBytes = [long]1000000 } }
        Mock Open-ReviewReport { $true }
        Mock Get-AllocatedFileSize { $null }
        Mock Test-RecycleBinCanHold { $true }
        Mock Send-FileToRecycleBin { 'failed' }
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    Context 'output' {
        It 'prints one JSON document that matches the schema' {
            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            @($run.Json -split "`n").Count | Should -Be 1
            (@($run.Data.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') | Should -Be ($script:reviewFields -join ',')
            $run.Data.schema_version | Should -Be 1
            $run.Data.command | Should -Be 'review'
            $run.Data.platform | Should -Be 'windows'
            $run.Data.token | Should -MatchExactly '^[0-9a-f]{8}$'
            $run.Data.token_expires_in_seconds | Should -Be 3600
            $run.Data.total_item_count | Should -Be 5
            $run.Data.total_size_bytes | Should -Be ($script:largeBytes + 500)
            $run.Data.truncated | Should -BeFalse
            $run.Data.report_opened | Should -BeTrue
            $run.Data.report_location_hint | Should -BeExactly '%LOCALAPPDATA%\disk-cleanup\review.html'
            $run.Data.selection_file_hint | Should -BeExactly 'Downloads/disk-cleanup-selection.json'
        }

        It 'reports both groups as an array of counts and totals' {
            $run = Invoke-Review

            $expected = '"groups":[{"id":"large-files","label":"Large files","item_count":3,"size_bytes":34603008,"status":"ok"},' +
                '{"id":"old-downloads","label":"Old items in Downloads","item_count":2,"size_bytes":500,"status":"ok"}]'
            $run.Json.Contains($expected) | Should -BeTrue
            $run.Json | Should -Match '"truncated":false'
            $run.Json | Should -Match '"total_item_count":5[,}]'
        }

        It 'keeps file names, folder names, paths and user names out of stdout' {
            $null = Add-SandboxReviewPruned -Sandbox $script:sandbox

            $run = Invoke-Review

            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
            foreach ($word in @('holiday', 'archive', 'installer', 'Videos', 'Documents', '.mp4', '.zip', '.iso')) {
                $run.Json | Should -Not -Match ([regex]::Escape($word))
            }
        }

        It 'still reports an empty array of groups with zero counts when nothing qualifies' {
            $run = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '9999', '--downloads-age-days', '9999')

            $run.ExitCode | Should -Be 0
            $run.Data.total_item_count | Should -Be 0
            $run.Data.total_size_bytes | Should -Be 0
            @($run.Data.groups).Count | Should -Be 2
            $run.Json | Should -Match '"groups":\[\{'
            (Get-SandboxManifestPathList -Manifest $script:sandbox.Manifest) | Should -BeNullOrEmpty
        }

        It 'reports report_opened false, not an error, when the report cannot be opened' {
            Mock Open-ReviewReport { $false }

            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $run.Data.report_opened | Should -BeFalse
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeTrue
        }

        It 'opens exactly the report file, once' {
            $null = Invoke-Review

            Should -Invoke Open-ReviewReport -Times 1 -Exactly
            Should -Invoke Open-ReviewReport -Times 1 -Exactly -ParameterFilter { $Path -like '*\disk-cleanup\review.html' }
        }

        It 'adds skipped_no_permission only when a folder could not be read' {
            Add-SandboxBigFile -Path (Join-Path -Path $script:sandbox.Home -ChildPath 'zqlocked\zqsecret.bin') -SizeMb 10
            Mock Get-ChildEntryList { [pscustomobject]@{ Entries = @(); Failed = $true } } -ParameterFilter { $Path -like '*\zqlocked' }

            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $run.Data.skipped_no_permission | Should -BeTrue
            $run.Data.total_item_count | Should -Be 5
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }

    Context 'a Downloads folder the app may not read' {
        It 'reports downloads_readable true and status ok for every group when Downloads can be listed' {
            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $run.Data.downloads_readable | Should -BeTrue
            (Get-ReviewGroup -Data $run.Data -Id 'large-files').status | Should -BeExactly 'ok'
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').status | Should -BeExactly 'ok'
            $run.Json | Should -Match '"downloads_readable":true'
        }

        It 'reports downloads_readable false and skips old-downloads when Downloads cannot be listed' {
            Mock Get-ChildEntryList { [pscustomobject]@{ Entries = @(); Failed = $true } } -ParameterFilter { $Path -like '*\zqfixtureuser\Downloads' }

            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $run.Json | Should -Match '"downloads_readable":false'
            $run.Data.skipped_no_permission | Should -BeTrue
            $downloads = Get-ReviewGroup -Data $run.Data -Id 'old-downloads'
            $downloads.status | Should -BeExactly 'skipped_no_permission'
            $downloads.item_count | Should -Be 0
            (Get-ReviewGroup -Data $run.Data -Id 'large-files').status | Should -BeExactly 'ok'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'reports downloads_readable null when there is no Downloads folder' {
            [System.IO.Directory]::Move($script:sandbox.Downloads, (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqdownloads-gone'))

            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $run.Json | Should -Match '"downloads_readable":null'
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').status | Should -BeExactly 'ok'
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 0
        }
    }

    Context 'what is listed' {
        It 'lists large files first, lets large-files win over old-downloads and numbers items from 1' {
            $null = Invoke-Review

            $leaves = Get-ManifestLeafList -Manifest $script:sandbox.Manifest
            ($leaves -join ',') | Should -Be 'zqholiday.mp4,zqarchive.zip,zqbig-old.iso,zqold-installer.exe,zqold-notes.txt'
            $lines = @([System.IO.File]::ReadAllLines($script:sandbox.Manifest))
            $lines[7] | Should -Match "^1`t12582912`t12582912`t[0-9]+`tlarge-files`t"
            $lines[9] | Should -Match "^3`t10485760`t10485760`t[0-9]+`tlarge-files`t"
            $lines[10] | Should -Match "^4`t300`t300`t[0-9]+`told-downloads`t"
        }

        It 'uses 100 MB and 90 days by default' {
            $run = Invoke-CleanupJson -Arguments @('review')

            (Get-ReviewGroup -Data $run.Data -Id 'large-files').item_count | Should -Be 0
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 3
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').size_bytes | Should -Be 10486260
        }

        It 'applies --min-size-mb' {
            $run = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '12')

            (Get-ReviewGroup -Data $run.Data -Id 'large-files').item_count | Should -Be 1
            (Get-ReviewGroup -Data $run.Data -Id 'large-files').size_bytes | Should -Be 12582912
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 3
        }

        It 'applies --downloads-age-days' {
            $run = Invoke-Review -Extra @('--downloads-age-days', '150')

            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 1
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').size_bytes | Should -Be 300
            (Get-ReviewGroup -Data $run.Data -Id 'large-files').item_count | Should -Be 3
        }

        It 'never lists small files, recent downloads, files below Downloads subfolders or empty files' {
            Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Downloads -ChildPath 'zqempty.txt') -SizeBytes 0 -AgeDays 300

            $null = Invoke-Review

            $leaves = Get-ManifestLeafList -Manifest $script:sandbox.Manifest
            foreach ($name in @('zqrecent.pdf', 'zqsmall.txt', 'zqnested-old.bin', 'zqempty.txt')) { $leaves | Should -Not -Contain $name }
        }

        It 'never lists its own selection files' {
            $selection = Add-SandboxSelection -Sandbox $script:sandbox -Token 'abcdef12' -Ids @(1)
            [System.IO.File]::SetLastWriteTimeUtc($selection, [System.DateTime]::UtcNow.AddDays(-300))

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 5
        }

        It 'never enters AppData, dot-directories, node_modules, Library or bundle folders' {
            $pruned = @(Add-SandboxReviewPruned -Sandbox $script:sandbox)

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 5
            $listed = @(Get-SandboxManifestPathList -Manifest $script:sandbox.Manifest)
            foreach ($path in $pruned) { $listed | Should -Not -Contain $path }
            $homeLength = (Get-NormalizedPath -Path $script:sandbox.Home).Length
            $relative = @($listed | ForEach-Object { $_.Substring($homeLength) })
            ($relative -join '|') | Should -Not -Match 'AppData|node_modules|photoslibrary|VMWAREVM|\.app\\|\.band\\|Library\\|\.zqhidden'
            $report = [System.IO.File]::ReadAllText($script:sandbox.Report)
            $report | Should -Not -Match 'zqdata\.bin|zqoriginal\.bin|zqdisk\.vmdk|zqbinary\.bin|zqtake\.bin'
        }

        It 'never follows a junction, in the profile or in Downloads' {
            Add-SandboxBigFile -Path (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqfar\zqoutside-big.bin') -SizeMb 15
            Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqfar\zqoutside-old.txt') -AgeDays 300
            Add-SandboxJunction -Link (Join-Path -Path $script:sandbox.Home -ChildPath 'zqlinked') -Target $script:sandbox.Outside
            $inner = Join-Path -Path $script:sandbox.Downloads -ChildPath 'zqlinked-too'
            Add-SandboxJunction -Link $inner -Target (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqfar')

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 5
            (Get-SandboxManifestPathList -Manifest $script:sandbox.Manifest) -join '|' | Should -Not -Match 'zqoutside'
        }

        It 'lists nothing below a Downloads folder that is itself a junction' {
            Move-SandboxFolderBehindJunction -Folder $script:sandbox.Downloads -NewLocation (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmoved-downloads')

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 2
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 0
        }

        It 'never lists a file symlink' {
            $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqlink-target.bin'
            Add-SandboxBigFile -Path $target -SizeMb 15
            $link = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos\zqlinked-video.mp4'
            try {
                New-Item -ItemType SymbolicLink -Path $link -Value $target -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
                return
            }

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 5
            [System.IO.File]::Delete($link)
        }

        It 'skips a file that occupies no space on disk' {
            Mock Get-AllocatedFileSize { [long]0 } -ParameterFilter { $Path -like '*zqholiday.mp4' }
            Mock Get-AllocatedFileSize { [long]0 } -ParameterFilter { $Path -like '*zqold-notes.txt' }

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 3
            (Get-ManifestLeafList -Manifest $script:sandbox.Manifest) | Should -Not -Contain 'zqholiday.mp4'
        }

        It 'counts what a sparse or compressed file really occupies' {
            Mock Get-AllocatedFileSize { [long]4096 } -ParameterFilter { $Path -like '*zqarchive.zip' }
            Mock Get-AllocatedFileSize { [long]4096 } -ParameterFilter { $Path -like '*zqbig-old.iso' }

            $run = Invoke-Review

            (Get-ReviewGroup -Data $run.Data -Id 'large-files').item_count | Should -Be 1
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').item_count | Should -Be 3
            (Get-ReviewGroup -Data $run.Data -Id 'old-downloads').size_bytes | Should -Be 4596
            (Get-ManifestLeafList -Manifest $script:sandbox.Manifest) | Should -Not -Contain 'zqarchive.zip'
        }

        It 'skips a cloud-only file marked Offline' {
            if (-not (Test-WindowsHost)) {
                Set-ItResult -Skipped -Because 'file attributes only exist on Windows'
                return
            }
            [System.IO.File]::SetAttributes($script:files.Holiday, [System.IO.FileAttributes]::Offline)

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 4
            (Get-ManifestLeafList -Manifest $script:sandbox.Manifest) | Should -Not -Contain 'zqholiday.mp4'
        }

        It 'skips hidden and system files' {
            if (-not (Test-WindowsHost)) {
                Set-ItResult -Skipped -Because 'file attributes only exist on Windows'
                return
            }
            [System.IO.File]::SetAttributes($script:files.Archive, [System.IO.FileAttributes]::Hidden)
            [System.IO.File]::SetAttributes($script:files.OldNotes, [System.IO.FileAttributes]::System)

            $run = Invoke-Review

            $run.Data.total_item_count | Should -Be 3
        }

        It 'keeps the 500 largest items and says so when more exist' {
            foreach ($number in 1..505) {
                $name = 'zqextra' + $number + '.tmp'
                Add-SandboxFile -Path (Join-Path -Path $script:sandbox.Downloads -ChildPath $name) -SizeBytes 10 -AgeDays 100
            }

            $run = Invoke-Review

            $run.Data.truncated | Should -BeTrue
            $run.Data.total_item_count | Should -Be 500
            $leaves = Get-ManifestLeafList -Manifest $script:sandbox.Manifest
            $leaves.Count | Should -Be 500
            ($leaves[0..4] -join ',') | Should -Be 'zqholiday.mp4,zqarchive.zip,zqbig-old.iso,zqold-installer.exe,zqold-notes.txt'
        }
    }

    Context 'side effects' {
        It 'deletes and moves nothing' {
            $null = Add-SandboxReviewPruned -Sandbox $script:sandbox
            $before = (Get-SandboxFileList -Root $script:sandbox.Base) -join '|'

            $run = Invoke-Review

            $run.ExitCode | Should -Be 0
            $own = @($script:sandbox.Manifest, $script:sandbox.Report)
            $after = @(Get-SandboxFileList -Root $script:sandbox.Base | Where-Object { $own -notcontains $_ })
            ($after -join '|') | Should -Be $before
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            @([System.IO.Directory]::GetFileSystemEntries($script:sandbox.Recycle)).Count | Should -Be 0
        }

        It 'does not change any modification time' {
            $before = [System.IO.File]::GetLastWriteTimeUtc($script:files.Archive).Ticks

            $null = Invoke-Review

            [System.IO.File]::GetLastWriteTimeUtc($script:files.Archive).Ticks | Should -Be $before
        }

        It 'writes the manifest and the report into the state directory only' {
            $run = Invoke-Review

            $lines = @([System.IO.File]::ReadAllLines($script:sandbox.Manifest))
            $lines[0] | Should -BeExactly 'disk-cleanup-review-manifest 1'
            $lines[1] | Should -BeExactly ('token ' + $run.Data.token)
            $lines[2] | Should -Match '^epoch [0-9]+$'
            $lines[3] | Should -BeExactly ('sha256 ' + (Get-SandboxManifestDigest -Manifest $script:sandbox.Manifest))
            $lines[4] | Should -MatchExactly '^secret [0-9a-f]{32}$'
            $lines[5] | Should -BeExactly 'min-size-mb 10'
            $lines[6] | Should -BeExactly 'downloads-age-days 90'
            $lines.Count | Should -Be 12
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeTrue
            @([System.IO.Directory]::GetFiles($script:sandbox.StateDir)).Count | Should -Be 2
        }

        It 'stores the thresholds it was run with in the manifest' {
            $null = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '12', '--downloads-age-days', '150')

            $lines = @([System.IO.File]::ReadAllLines($script:sandbox.Manifest))
            $lines[5] | Should -BeExactly 'min-size-mb 12'
            $lines[6] | Should -BeExactly 'downloads-age-days 150'
        }

        It 'keeps the selection secret out of stdout and gives it only to the manifest and the report' {
            $first = Invoke-Review
            $firstSecret = Get-SandboxSecret -Manifest $script:sandbox.Manifest
            $report = [System.IO.File]::ReadAllText($script:sandbox.Report)
            $second = Invoke-Review
            $secondSecret = Get-SandboxSecret -Manifest $script:sandbox.Manifest

            $firstSecret | Should -MatchExactly '^[0-9a-f]{32}$'
            $secondSecret | Should -Not -Be $firstSecret
            $first.Json | Should -Not -Match $firstSecret
            $second.Json | Should -Not -Match $secondSecret
            $first.Json | Should -Not -Match '(?i)secret'
            $first.Json | Should -Not -Match '[0-9a-f]{32}'
            $report.Contains('<body data-token="' + $first.Data.token + '" data-secret="' + $firstSecret + '">') | Should -BeTrue
            ([regex]::Matches($report, $firstSecret)).Count | Should -Be 1
        }

        It 'keeps the selection secret out of the error document too' {
            Mock Write-ReviewStateFile { throw ('zqboom ' + $Text) }

            $run = Invoke-Review

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'INTERNAL'
            $run.Json | Should -Not -Match '[0-9a-f]{32}'
        }

        It 'gives every run a new token and replaces the previous manifest' {
            $first = Invoke-Review
            $second = Invoke-Review

            $second.Data.token | Should -Not -Be $first.Data.token
            [System.IO.File]::ReadAllText($script:sandbox.Manifest) | Should -Not -Match $first.Data.token
        }

        It 'refuses to write through a state directory that is a junction' {
            Add-SandboxJunction -Link $script:sandbox.StateDir -Target $script:sandbox.Outside

            $run = Invoke-Review

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'INTERNAL'
            @([System.IO.Directory]::GetFiles($script:sandbox.Outside)).Count | Should -Be 0
            Should -Invoke Open-ReviewReport -Times 0 -Exactly
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'does not leak anything when the walk fails unexpectedly' {
            Mock Get-ReviewCandidateList { throw 'zqboom at C:\zqsecret\zqholiday.mp4' }

            $run = Invoke-Review

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'INTERNAL'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }

    Context 'a review that outlived its token' {
        BeforeEach {
            Mock Test-AppRunning { $false }
            Mock Get-RunningPackageFamilyList { @() }
            Mock Get-RecycleBinInfo { [pscustomobject]@{ Available = $true; Bytes = [long]0; Items = 0 } }
            Mock Invoke-RecycleBinEmpty { $true }
            Mock Get-ToolPath { $null }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        }

        It 'discards the report and the manifest when <Name> starts 60 minutes later' -ForEach @(
            @{ Name = 'scan'; Arguments = @('scan') }
            @{ Name = 'clean'; Arguments = @('clean', '--token', 'abcdef12', '--categories', 'temp-files') }
            @{ Name = 'review-apply'; Arguments = @('review-apply', '--token', 'abcdef12') }
            @{ Name = 'help'; Arguments = @('--help') }
            @{ Name = 'version'; Arguments = @('--version') }
            @{ Name = 'a command line that is not valid'; Arguments = @('zqnonsense') }
        ) {
            $null = Invoke-Review
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3600))
            $personal = @(Get-SandboxFileList -Root $script:sandbox.Home | Where-Object { $_ -notlike '*\AppData\*' })

            $run = Invoke-CleanupJson -Arguments ([string[]]$Arguments)

            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeFalse
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeFalse
            foreach ($path in $personal) { Test-Path -LiteralPath $path | Should -BeTrue }
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'replaces an expired review with the new one when review starts' {
            $first = Invoke-Review
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 7200))

            $second = Invoke-Review

            $second.ExitCode | Should -Be 0
            $second.Data.token | Should -Not -Be $first.Data.token
            [System.IO.File]::ReadAllText($script:sandbox.Manifest) | Should -Match ('token ' + $second.Data.token)
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeTrue
        }

        It 'keeps a review that is 59 minutes old when <Name> starts' -ForEach @(
            @{ Name = 'scan'; Arguments = @('scan') }
            @{ Name = 'version'; Arguments = @('--version') }
        ) {
            $null = Invoke-Review
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3540))

            $null = Invoke-CleanupJson -Arguments ([string[]]$Arguments)

            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeTrue
        }

        It 'dates a review whose manifest cannot be read by its files: <Name>' -ForEach @(
            @{ Name = 'two hours old, discarded'; AgeMinutes = 120; Kept = $false }
            @{ Name = 'ten minutes old, kept'; AgeMinutes = 10; Kept = $true }
        ) {
            $null = Invoke-Review
            [System.IO.File]::WriteAllText($script:sandbox.Manifest, 'zqnot a manifest')
            $stamp = [System.DateTime]::UtcNow.AddMinutes(-1 * $AgeMinutes)
            [System.IO.File]::SetLastWriteTimeUtc($script:sandbox.Manifest, $stamp)
            [System.IO.File]::SetLastWriteTimeUtc($script:sandbox.Report, $stamp)

            $null = Invoke-CleanupJson -Arguments @('--version')

            Test-Path -LiteralPath $script:sandbox.Manifest | Should -Be $Kept
            Test-Path -LiteralPath $script:sandbox.Report | Should -Be $Kept
        }

        It 'discards a report that was left behind without a manifest' {
            $null = Invoke-Review
            [System.IO.File]::Move($script:sandbox.Manifest, (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmanifest-away'))
            [System.IO.File]::SetLastWriteTimeUtc($script:sandbox.Report, [System.DateTime]::UtcNow.AddMinutes(-61))

            $null = Invoke-CleanupJson -Arguments @('--help')

            Test-Path -LiteralPath $script:sandbox.Report | Should -BeFalse
        }

        It 'does nothing and does not create the state directory when there is no review' {
            $run = Invoke-CleanupJson -Arguments @('--version')

            $run.ExitCode | Should -Be 0
            Test-Path -LiteralPath $script:sandbox.StateDir | Should -BeFalse
        }

        It 'never fails a command when the old review cannot be discarded' {
            $null = Invoke-Review
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3600))
            Mock Invoke-GuardedDelete { throw 'zqboom at C:\zqsecret\zqholiday.mp4' }

            $run = Invoke-CleanupJson -Arguments @('--version')

            $run.ExitCode | Should -Be 0
            $run.Data.command | Should -Be 'version'
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }
    }

    Context 'next to a scan' {
        BeforeEach {
            Add-SandboxCache -Sandbox $script:sandbox
            Mock Test-AppRunning { $false }
            Mock Get-RunningPackageFamilyList { @() }
            Mock Get-RecycleBinInfo { [pscustomobject]@{ Available = $true; Bytes = [long]0; Items = 0 } }
            Mock Invoke-RecycleBinEmpty { $true }
            Mock Get-ToolPath { $null }
            Mock Invoke-Tool { [pscustomobject]@{ ExitCode = 1; Output = @() } }
        }

        It 'does not invalidate a scan token' {
            $scanToken = [string](Invoke-CleanupJson -Arguments @('scan')).Data.token
            $null = Invoke-Review

            $clean = Invoke-CleanupJson -Arguments @('clean', '--token', $scanToken, '--categories', 'temp-files')

            $clean.ExitCode | Should -Be 0
            (Get-ResultEntry -Data $clean.Data -Id 'temp-files').status | Should -Be 'cleaned'
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
        }

        It 'is not invalidated by a scan, and a scan token is not a review token' {
            $reviewToken = [string](Invoke-Review).Data.token
            $scanToken = [string](Invoke-CleanupJson -Arguments @('scan')).Data.token

            $wrong = Invoke-CleanupJson -Arguments @('review-apply', '--token', $scanToken)
            $clean = Invoke-CleanupJson -Arguments @('clean', '--token', $reviewToken, '--categories', 'temp-files')

            $wrong.Data.error.code | Should -Be 'TOKEN_INVALID'
            $clean.Data.error.code | Should -Be 'TOKEN_INVALID'
            [System.IO.File]::ReadAllText($script:sandbox.Manifest) | Should -Match ('token ' + $reviewToken)
        }
    }
}

Describe 'review guard' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:files = [pscustomobject]@{
            Holiday  = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos\zqholiday.mp4'
            OldNotes = Join-Path -Path $script:sandbox.Downloads -ChildPath 'zqold-notes.txt'
        }
        Add-SandboxFile -Path $script:files.Holiday
        Add-SandboxFile -Path $script:files.OldNotes
        $script:roots = Get-ReviewRoot
        $script:good = Get-NormalizedPath -Path $script:files.Holiday
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'allows a real file inside the user profile, spelled as Windows stores it' {
        Test-ReviewPathAllowed -Path $script:good -Roots $script:roots | Should -BeTrue
        Test-ReviewPathAllowed -Path (Get-NormalizedPath -Path $script:files.OldNotes) -Roots $script:roots | Should -BeTrue
    }

    It 'refuses an empty, relative or wildcard path: "<Value>"' -ForEach @(
        @{ Value = '' }
        @{ Value = 'Videos\zqholiday.mp4' }
        @{ Value = '..\zqholiday.mp4' }
        @{ Value = 'C:zqholiday.mp4' }
        @{ Value = 'C:\zq*\zqholiday.mp4' }
        @{ Value = 'C:\zq?\zqholiday.mp4' }
    ) {
        Test-ReviewPathAllowed -Path $Value -Roots $script:roots | Should -BeFalse
    }

    It 'refuses the user profile itself and anything outside it' {
        $outside = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqkeep.bin'
        Add-SandboxFile -Path $outside

        Test-ReviewPathAllowed -Path $script:roots.Home -Roots $script:roots | Should -BeFalse
        Test-ReviewPathAllowed -Path (Get-NormalizedPath -Path $outside) -Roots $script:roots | Should -BeFalse
        Test-ReviewPathAllowed -Path (Get-NormalizedPath -Path $script:sandbox.Base) -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a file inside <Name>' -ForEach @(
        @{ Name = 'AppData'; Relative = 'AppData\Local\zqapp\zqdata.bin' }
        @{ Name = 'the state directory'; Relative = 'AppData\Local\disk-cleanup\review-manifest' }
        @{ Name = 'a dot-directory'; Relative = '.zqhidden\zqbig.bin' }
        @{ Name = 'node_modules'; Relative = 'zqproject\node_modules\zqpackage\zqbig.bin' }
        @{ Name = 'Library'; Relative = 'Library\zqbig.bin' }
        @{ Name = 'a photo library'; Relative = 'Pictures\zqPhotos.photoslibrary\zqoriginal.bin' }
        @{ Name = 'a virtual machine bundle'; Relative = 'zqMachine.VMWAREVM\zqdisk.vmdk' }
        @{ Name = 'an app bundle below a normal folder'; Relative = 'zqApps\zqTool.app\zqdeep\zqbinary.bin' }
    ) {
        $path = Join-Path -Path $script:sandbox.Home -ChildPath $Relative
        Add-SandboxFile -Path $path

        Test-ReviewPathAllowed -Path (Get-NormalizedPath -Path $path) -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a path that is not spelled exactly as stored: <Name>' -ForEach @(
        @{ Name = 'other letter case'; Kind = 'case' }
        @{ Name = 'dot-dot segment'; Kind = 'dots' }
        @{ Name = 'trailing separator'; Kind = 'slash' }
        @{ Name = 'forward slashes'; Kind = 'forward' }
    ) {
        $parent = [System.IO.Path]::GetDirectoryName($script:good)
        $leaf = [System.IO.Path]::GetFileName($script:good)
        $variant = $script:good.ToUpperInvariant()
        if ($Kind -eq 'dots') { $variant = $parent + '\..\Videos\' + $leaf }
        if ($Kind -eq 'slash') { $variant = $script:good + '\' }
        if ($Kind -eq 'forward') { $variant = $script:good.Replace('\', '/') }

        Test-ReviewPathAllowed -Path $variant -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a path of 260 characters or more without failing' {
        $long = $script:roots.Home + '\' + ('a' * 260) + '.bin'

        Test-ReviewPathAllowed -Path $long -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a name with a control character without failing' {
        $odd = $script:roots.Home + '\zqodd' + [char]9 + 'name.bin'

        Test-ReviewPathAllowed -Path $odd -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a file below a folder whose name carries a character that reorders text' {
        $path = Join-Path -Path $script:sandbox.Home -ChildPath ('Videos\zq' + [char]8238 + 'gpj\zqclip.mp4')
        try {
            Add-SandboxFile -Path $path
        } catch {
            Set-ItResult -Skipped -Because 'this file system does not accept the folder name'
            return
        }

        Test-ReviewPathAllowed -Path (Get-NormalizedPath -Path $path) -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a file that does not exist' {
        Test-ReviewPathAllowed -Path ($script:roots.Home + '\Videos\zqmissing.mp4') -Roots $script:roots | Should -BeFalse
    }

    It 'refuses a file whose folder was replaced by a junction' {
        $videos = Join-Path -Path $script:sandbox.Home -ChildPath 'Videos'
        Move-SandboxFolderBehindJunction -Folder $videos -NewLocation (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqmoved-videos')

        Test-Path -LiteralPath $script:good | Should -BeTrue
        Test-ReviewPathAllowed -Path $script:good -Roots $script:roots | Should -BeFalse
    }

    It 'treats the name "<Label>" as safe: <Expected>' -ForEach @(
        @{ Label = 'plain'; Name = 'zq holiday (1).mp4'; Expected = $true }
        @{ Label = 'shell characters'; Name = 'zq$(calc)`[1]&''%TEMP%;.bin'; Expected = $true }
        @{ Label = 'accented letter'; Name = ('zqcaf' + [char]233 + '.txt'); Expected = $true }
        @{ Label = 'tab'; Name = ('zq' + [char]9 + 'x'); Expected = $false }
        @{ Label = 'line feed'; Name = ('zq' + [char]10 + 'x'); Expected = $false }
        @{ Label = 'carriage return'; Name = ('zq' + [char]13 + 'x'); Expected = $false }
        @{ Label = 'delete character'; Name = ('zq' + [char]127 + 'x'); Expected = $false }
        @{ Label = 'line separator'; Name = ('zq' + [char]8232 + 'x'); Expected = $false }
        @{ Label = 'right-to-left override'; Name = ('zq' + [char]8238 + 'x'); Expected = $false }
        @{ Label = 'left-to-right embedding'; Name = ('zq' + [char]8234 + 'x'); Expected = $false }
        @{ Label = 'pop directional formatting'; Name = ('zq' + [char]8236 + 'x'); Expected = $false }
        @{ Label = 'left-to-right isolate'; Name = ('zq' + [char]8294 + 'x'); Expected = $false }
        @{ Label = 'pop directional isolate'; Name = ('zq' + [char]8297 + 'x'); Expected = $false }
        @{ Label = 'left-to-right mark'; Name = ('zq' + [char]8206 + 'x'); Expected = $false }
        @{ Label = 'right-to-left mark'; Name = ('zq' + [char]8207 + 'x'); Expected = $false }
        @{ Label = 'Arabic letter mark'; Name = ('zq' + [char]1564 + 'x'); Expected = $false }
        @{ Label = 'Arabic letters'; Name = ('zq' + [char]1587 + [char]1604 + '.txt'); Expected = $true }
        @{ Label = 'empty'; Name = ''; Expected = $false }
    ) {
        Test-ReviewNameSafe -Name $Name | Should -Be $Expected
    }

    It 'treats attributes <Value> as a cloud placeholder: <Expected>' -ForEach @(
        @{ Value = 4096; Expected = $true }
        @{ Value = 262144; Expected = $true }
        @{ Value = 4194304; Expected = $true }
        @{ Value = 4194336; Expected = $true }
        @{ Value = 5248544; Expected = $true }
        @{ Value = 32; Expected = $false }
        @{ Value = 128; Expected = $false }
        @{ Value = 2592; Expected = $false }
    ) {
        Test-CloudPlaceholderAttribute -Attributes $Value | Should -Be $Expected
    }

    It 'treats the folder name <Name> as pruned: <Expected>' -ForEach @(
        @{ Name = 'AppData'; Expected = $true }
        @{ Name = 'appdata'; Expected = $true }
        @{ Name = '.git'; Expected = $true }
        @{ Name = 'node_modules'; Expected = $true }
        @{ Name = '$RECYCLE.BIN'; Expected = $true }
        @{ Name = 'Family.photoslibrary'; Expected = $true }
        @{ Name = 'Work.SPARSEBUNDLE'; Expected = $true }
        @{ Name = 'Catalog.lrdata'; Expected = $true }
        @{ Name = 'Project.xcodeproj'; Expected = $true }
        @{ Name = 'Videos'; Expected = $false }
        @{ Name = 'apps'; Expected = $false }
        @{ Name = 'my.application'; Expected = $false }
    ) {
        Test-ReviewDirectoryPruned -Name $Name | Should -Be $Expected
    }
}
