BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    function Invoke-Apply {
        param([string]$Token)
        return (Invoke-CleanupJson -Arguments @('review-apply', '--token', $Token))
    }

    function Add-RawSelection {
        param($Sandbox, [string]$Content, [string]$Name = 'disk-cleanup-selection.json', [string]$Folder = '')
        if ($Folder.Length -eq 0) { $Folder = $Sandbox.Downloads }
        [void][System.IO.Directory]::CreateDirectory($Folder)
        $path = Join-Path -Path $Folder -ChildPath $Name
        [System.IO.File]::WriteAllText($path, $Content, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
        return $path
    }

    function Get-OtherToken {
        param([string]$Token)
        if ($Token -ceq 'abcdef12') { return '12abcdef' }
        return 'abcdef12'
    }
}

Describe 'review-apply selection file and token' {
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
        Mock Send-FileToRecycleBin {
            $name = [System.Guid]::NewGuid().ToString('N') + '-' + [System.IO.Path]::GetFileName($Path)
            [System.IO.File]::Move($Path, [System.IO.Path]::Combine($script:recycleDir, $name))
            'trashed'
        }
        $script:token = Invoke-ReviewForToken
        $script:otherToken = Get-OtherToken -Token $script:token
        $script:secret = Get-SandboxSecret -Manifest $script:sandbox.Manifest
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    Context 'finding the selection' {
        It 'reports SELECTION_NOT_FOUND when nothing was saved, and keeps the token usable' {
            $missing = Invoke-Apply -Token $script:token
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)
            $second = Invoke-Apply -Token $script:token

            $missing.ExitCode | Should -Be 1
            $missing.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
            $missing.Data.error.message | Should -Not -BeNullOrEmpty
            Assert-PrivateOutput -Json $missing.Json -Sandbox $script:sandbox
            $second.ExitCode | Should -Be 0
            $second.Data.trashed_count | Should -Be 1
        }

        It 'reports SELECTION_NO_PERMISSION when Downloads cannot be listed, moves nothing and keeps the token' {
            $mine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)
            $script:lockDownloads = $true
            Mock Get-ChildEntryList { [pscustomobject]@{ Entries = @(); Failed = $true } } -ParameterFilter { $script:lockDownloads -and ($Path -like '*\zqfixtureuser\Downloads') }

            $locked = Invoke-Apply -Token $script:token
            $script:lockDownloads = $false
            $second = Invoke-Apply -Token $script:token

            $locked.ExitCode | Should -Be 1
            $locked.Data.error.code | Should -BeExactly 'SELECTION_NO_PERMISSION'
            $locked.Data.error.message | Should -Match 'Downloads'
            Assert-PrivateOutput -Json $locked.Json -Sandbox $script:sandbox
            $second.ExitCode | Should -Be 0
            $second.Data.trashed_count | Should -Be 1
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
            Test-Path -LiteralPath $mine | Should -BeFalse
        }

        It 'reports SELECTION_NO_PERMISSION when only the Desktop cannot be listed and nothing was found' {
            [void][System.IO.Directory]::CreateDirectory($script:sandbox.Desktop)
            Mock Get-ChildEntryList { [pscustomobject]@{ Entries = @(); Failed = $true } } -ParameterFilter { $Path -like '*\zqfixtureuser\Desktop' }

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -BeExactly 'SELECTION_NO_PERMISSION'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
        }

        It 'still uses a selection in Downloads when only the Desktop cannot be listed' {
            [void][System.IO.Directory]::CreateDirectory($script:sandbox.Desktop)
            $mine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)
            Mock Get-ChildEntryList { [pscustomobject]@{ Entries = @(); Failed = $true } } -ParameterFilter { $Path -like '*\zqfixtureuser\Desktop' }

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $mine | Should -BeFalse
        }

        It 'reports SELECTION_NOT_FOUND when there is no Downloads folder' {
            [System.IO.Directory]::Move($script:sandbox.Downloads, (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqdownloads-gone'))

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
        }

        It 'does not look through a Downloads folder that is a junction' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            Move-SandboxFolderBehindJunction -Folder $script:sandbox.Downloads -NewLocation (Join-Path -Path $script:sandbox.Outside -ChildPath 'zqdownloads-moved')

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }

        It 'ignores a file named "<Name>"' -ForEach @(
            @{ Name = 'disk-cleanup-selection.json.txt' }
            @{ Name = 'my-disk-cleanup-selection.json' }
            @{ Name = 'disk-cleanup-selection (x).json' }
            @{ Name = 'disk-cleanup-selection(1).json' }
            @{ Name = 'disk-cleanup-selection-1-2.json' }
            @{ Name = 'disk-cleanup-selection (1234).json' }
            @{ Name = 'disk-cleanup-selections.json' }
            @{ Name = 'Disk-Cleanup-Selection.JSON' }
            @{ Name = 'disk-cleanup-selection 1234.json' }
            @{ Name = 'disk-cleanup-selection x.json' }
        ) {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Name $Name

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
        }

        It 'accepts the browser duplicate name "<Name>"' -ForEach @(
            @{ Name = 'disk-cleanup-selection (1).json' }
            @{ Name = 'disk-cleanup-selection (27).json' }
            @{ Name = 'disk-cleanup-selection-3.json' }
            @{ Name = 'disk-cleanup-selection 2.json' }
        ) {
            $selection = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Name $Name

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $selection | Should -BeFalse
        }

        It 'ignores a selection file in a subfolder and a folder with the selection name' {
            $nested = Join-Path -Path $script:sandbox.Downloads -ChildPath 'zqsub'
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            [System.IO.File]::Move((Join-Path -Path $script:sandbox.Downloads -ChildPath 'disk-cleanup-selection.json'), (Join-Path -Path $nested -ChildPath 'disk-cleanup-selection.json'))
            [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $script:sandbox.Downloads -ChildPath 'disk-cleanup-selection.json'))

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
        }

        It 'ignores a selection file that is a symbolic link' {
            $real = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            $target = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqselection-target.json'
            [System.IO.File]::Move($real, $target)
            try {
                New-Item -ItemType SymbolicLink -Path $real -Value $target -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'creating symbolic links needs a privilege this session lacks'
                return
            }

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
            Test-Path -LiteralPath $target | Should -BeTrue
            [System.IO.File]::Delete($real)
        }

        It 'lets the newest valid selection win' {
            $older = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            $newer = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2) -Name 'disk-cleanup-selection (1).json'
            [System.IO.File]::SetLastWriteTimeUtc($older, [System.DateTime]::UtcNow.AddMinutes(-10))
            [System.IO.File]::SetLastWriteTimeUtc($newer, [System.DateTime]::UtcNow.AddMinutes(-1))

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:files.Archive | Should -BeFalse
            Test-Path -LiteralPath $older | Should -BeFalse
            Test-Path -LiteralPath $newer | Should -BeFalse
        }

        It 'skips a newer selection of another review and uses the one with this token' {
            $mine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4)
            $foreign = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:otherToken -Ids @(1) -Name 'disk-cleanup-selection (1).json'
            [System.IO.File]::SetLastWriteTimeUtc($mine, [System.DateTime]::UtcNow.AddMinutes(-10))

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldInstaller | Should -BeFalse
            Test-Path -LiteralPath $foreign | Should -BeTrue
        }
    }

    Context 'a selection saved on the Desktop' {
        It 'uses a selection on the Desktop and removes only that file from the Desktop' {
            $desk = $script:sandbox.Desktop
            $mine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Folder $desk
            $notes = Join-Path -Path $desk -ChildPath 'zqdesk-notes.txt'
            Add-SandboxFile -Path $notes -SizeBytes 40 -AgeDays 3
            $foreign = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:otherToken -Ids @(2) -Name 'disk-cleanup-selection-9.json' -Folder $desk
            $broken = Add-RawSelection -Sandbox $script:sandbox -Content ('zqnot a selection ' + $script:token) -Name 'disk-cleanup-selection (2).json' -Folder $desk
            $lookalike = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2) -Name 'zqdisk-cleanup-selection.json' -Folder $desk
            $nested = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2) -Folder (Join-Path -Path $desk -ChildPath 'zqsub')
            $deskBefore = @([System.IO.Directory]::GetFiles($desk)).Count

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeFalse
            Test-Path -LiteralPath $script:files.Archive | Should -BeTrue
            Test-Path -LiteralPath $mine | Should -BeFalse
            Test-Path -LiteralPath $notes | Should -BeTrue
            Test-Path -LiteralPath $foreign | Should -BeTrue
            Test-Path -LiteralPath $broken | Should -BeTrue
            Test-Path -LiteralPath $lookalike | Should -BeTrue
            Test-Path -LiteralPath $nested | Should -BeTrue
            @([System.IO.Directory]::GetFiles($desk)).Count | Should -Be ($deskBefore - 1)
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'lets the newest valid selection win across Downloads and the Desktop, and consumes every copy' {
            $older = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)
            $newer = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Name 'disk-cleanup-selection (1).json' -Folder $script:sandbox.Desktop
            [System.IO.File]::SetLastWriteTimeUtc($older, [System.DateTime]::UtcNow.AddMinutes(-10))
            [System.IO.File]::SetLastWriteTimeUtc($newer, [System.DateTime]::UtcNow.AddMinutes(-1))

            $run = Invoke-Apply -Token $script:token

            $run.Data.selected_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeFalse
            Test-Path -LiteralPath $script:files.Archive | Should -BeTrue
            Test-Path -LiteralPath $older | Should -BeFalse
            Test-Path -LiteralPath $newer | Should -BeFalse
        }

        It 'prefers a newer selection in Downloads over an older one on the Desktop' {
            $older = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Folder $script:sandbox.Desktop
            $newer = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)
            [System.IO.File]::SetLastWriteTimeUtc($older, [System.DateTime]::UtcNow.AddMinutes(-10))
            [System.IO.File]::SetLastWriteTimeUtc($newer, [System.DateTime]::UtcNow.AddMinutes(-1))

            $run = Invoke-Apply -Token $script:token

            $run.Data.selected_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Archive | Should -BeFalse
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $older | Should -BeFalse
        }

        It 'ignores invalid selections on the Desktop and leaves them alone' {
            $valid = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(2)
            [System.IO.File]::SetLastWriteTimeUtc($valid, [System.DateTime]::UtcNow.AddMinutes(-10))
            $desk = $script:sandbox.Desktop
            $forged = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1]}') -Folder $desk
            $wrong = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Name 'disk-cleanup-selection (1).json' -Secret '0123456789abcdef0123456789abcdef' -Folder $desk
            $padding = New-Object -TypeName string -ArgumentList ([char]32), 1048577
            $huge = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","secret":"' + $script:secret + '","ids":[1]}' + $padding) -Name 'disk-cleanup-selection-2.json' -Folder $desk

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Archive | Should -BeFalse
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $forged | Should -BeTrue
            Test-Path -LiteralPath $wrong | Should -BeTrue
            Test-Path -LiteralPath $huge | Should -BeTrue
        }

        It 'reports SELECTION_INVALID when only invalid selections are on the Desktop' {
            $forged = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1]}') -Folder $script:sandbox.Desktop

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $forged | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
        }

        It 'does not look through a Desktop that is a junction' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1) -Folder $script:sandbox.Desktop
            $moved = Join-Path -Path $script:sandbox.Outside -ChildPath 'zqdesktop-moved'
            Move-SandboxFolderBehindJunction -Folder $script:sandbox.Desktop -NewLocation $moved

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_NOT_FOUND'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path -Path $moved -ChildPath 'disk-cleanup-selection.json') | Should -BeTrue
        }
    }

    Context 'rejecting a selection' {
        It 'rejects a forged selection that has the token but no secret, and leaves the file alone' {
            $forged = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1,2,3,4,5]}')
            $before = @(Get-SandboxFileList -Root $script:sandbox.Home) -join '|'

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            (@(Get-SandboxFileList -Root $script:sandbox.Home) -join '|') | Should -Be $before
            Test-Path -LiteralPath $forged | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'rejects a selection whose secret is <Name>, and leaves the file alone' -ForEach @(
            @{ Name = 'another secret'; Kind = 'other' }
            @{ Name = 'in upper case'; Kind = 'upper' }
            @{ Name = 'the right secret cut short'; Kind = 'short' }
            @{ Name = 'the right secret with one more character'; Kind = 'long' }
            @{ Name = 'empty'; Kind = 'empty' }
            @{ Name = 'the token'; Kind = 'token' }
        ) {
            $wrong = '0123456789abcdef0123456789abcdef'
            if ($wrong -ceq $script:secret) { $wrong = 'fedcba9876543210fedcba9876543210' }
            if ($Kind -eq 'upper') { $wrong = 'A' + $script:secret.Substring(1).ToUpperInvariant() }
            if ($Kind -eq 'short') { $wrong = $script:secret.Substring(0, 31) }
            if ($Kind -eq 'long') { $wrong = $script:secret + '0' }
            if ($Kind -eq 'empty') { $wrong = '' }
            if ($Kind -eq 'token') { $wrong = $script:token }
            $forged = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","secret":"' + $wrong + '","ids":[1,4]}')

            $run = Invoke-Apply -Token $script:token

            $wrong | Should -Not -BeExactly $script:secret
            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $forged | Should -BeTrue
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
        }

        It 'keeps the token usable after a forged selection, for the selection the page saved' {
            $forged = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1]}')
            $refused = Invoke-Apply -Token $script:token
            $genuine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5) -Name 'disk-cleanup-selection (1).json'

            $run = Invoke-Apply -Token $script:token

            $refused.Data.error.code | Should -Be 'SELECTION_INVALID'
            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldNotes | Should -BeFalse
            Test-Path -LiteralPath $genuine | Should -BeFalse
            Test-Path -LiteralPath $forged | Should -BeTrue
        }

        It 'never prints the secret, whatever review-apply answers' {
            $missing = Invoke-Apply -Token $script:token
            $null = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1]}')
            $refused = Invoke-Apply -Token $script:token
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)
            $applied = Invoke-Apply -Token $script:token

            $applied.ExitCode | Should -Be 0
            foreach ($run in @($missing, $refused, $applied)) { $run.Json | Should -Not -Match $script:secret }
        }

        It 'rejects a selection that carries another token and keeps this token usable' {
            $foreign = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:otherToken -Ids @(1, 2, 3)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $foreign | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'rejects a selection larger than 1 MB even when it is otherwise well formed' {
            $padding = New-Object -TypeName string -ArgumentList ([char]32), 1048577
            $big = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","secret":"' + $script:secret + '","ids":[1]}' + $padding)

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $big | Should -BeTrue
        }

        It 'accepts a selection of exactly 1 MB' {
            $prefix = '{"token":"' + $script:token + '","secret":"' + $script:secret + '","ids":[5]}'
            $padding = New-Object -TypeName string -ArgumentList ([char]32), (1048576 - $prefix.Length)
            $null = Add-RawSelection -Sandbox $script:sandbox -Content ($prefix + $padding)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
        }

        It 'rejects malformed content: <Name>' -ForEach @(
            @{ Name = 'empty file'; Template = '' }
            @{ Name = 'trailing comma'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1,]}' }
            @{ Name = 'keys in another order'; Template = '{"ids":[1],"secret":"SECRET","token":"TOKEN"}' }
            @{ Name = 'an extra key'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1],"all":true}' }
            @{ Name = 'text after the document'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1]} $(calc)' }
            @{ Name = 'text before the document'; Template = 'x{"token":"TOKEN","secret":"SECRET","ids":[1]}' }
            @{ Name = 'a second document'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1]}{"token":"TOKEN","secret":"SECRET","ids":[2]}' }
            @{ Name = 'ids as strings'; Template = '{"token":"TOKEN","secret":"SECRET","ids":["1"]}' }
            @{ Name = 'a negative id'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[-1]}' }
            @{ Name = 'a fractional id'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1.5]}' }
            @{ Name = 'an exponent'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1e3]}' }
            @{ Name = 'an id of seven digits'; Template = '{"token":"TOKEN","secret":"SECRET","ids":[1234567]}' }
            @{ Name = 'a path instead of an id'; Template = '{"token":"TOKEN","secret":"SECRET","ids":["C:\\Users"]}' }
            @{ Name = 'ids not in an array'; Template = '{"token":"TOKEN","secret":"SECRET","ids":1}' }
            @{ Name = 'single quotes'; Template = '{''token'':''TOKEN'',''secret'':''SECRET'',''ids'':[1]}' }
            @{ Name = 'an upper-case token'; Template = '{"token":"ABCDEF12","secret":"SECRET","ids":[1]}' }
            @{ Name = 'a token with a space'; Template = '{"token":"TOKEN ","secret":"SECRET","ids":[1]}' }
            @{ Name = 'a bare array'; Template = '[1,2,3]' }
            @{ Name = 'PowerShell code'; Template = '$(throw "zqevaluated"); {"token":"TOKEN","secret":"SECRET","ids":[1]}' }
            @{ Name = 'the secret before the token'; Template = '{"secret":"SECRET","token":"TOKEN","ids":[1]}' }
            @{ Name = 'the secret after the ids'; Template = '{"token":"TOKEN","ids":[1],"secret":"SECRET"}' }
            @{ Name = 'the secret twice'; Template = '{"token":"TOKEN","secret":"SECRET","secret":"SECRET","ids":[1]}' }
            @{ Name = 'a secret with a space'; Template = '{"token":"TOKEN","secret":"SECRET ","ids":[1]}' }
            @{ Name = 'a secret that is not a string'; Template = '{"token":"TOKEN","secret":1,"ids":[1]}' }
            @{ Name = 'an escaped key'; Template = '{"\u0074oken":"TOKEN","secret":"SECRET","ids":[1]}' }
        ) {
            $bad = Add-RawSelection -Sandbox $script:sandbox -Content $Template.Replace('TOKEN', $script:token).Replace('SECRET', $script:secret)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $bad | Should -BeTrue
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'tolerates whitespace and a byte order mark' {
            $lineBreak = [string][char]13 + [char]10
            $content = [string][char]65279 + ' {' + $lineBreak + '  "token" : "' + $script:token + '" ,' + $lineBreak +
                '  "secret" : "' + $script:secret + '" ,' + $lineBreak +
                '  "ids" : [ 5 ,' + [char]9 + '4 ]' + $lineBreak + '}' + $lineBreak
            $null = Add-RawSelection -Sandbox $script:sandbox -Content $content

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.selected_count | Should -Be 2
            $run.Data.trashed_count | Should -Be 2
        }

        It 'parses a selection without ever treating it as JSON or code' {
            Mock ConvertFrom-Json { throw 'zqmust-not-parse' }
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)

            $outcome = Invoke-Cleanup -Arguments @('review-apply', '--token', $script:token)

            $outcome.ExitCode | Should -Be 0
            $outcome.Json | Should -Match '"trashed_count":1[,}]'
        }
    }

    Context 'token' {
        It 'is single-use and leaves none of its own files behind' {
            $selection = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4)
            $first = Invoke-Apply -Token $script:token
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $second = Invoke-Apply -Token $script:token

            $first.ExitCode | Should -Be 0
            $second.ExitCode | Should -Be 1
            $second.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeFalse
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeFalse
            Test-Path -LiteralPath $selection | Should -BeTrue
            Should -Invoke Send-FileToRecycleBin -Times 1 -Exactly
            Assert-PrivateOutput -Json $second.Json -Sandbox $script:sandbox
        }

        It 'removes only its own selection files from Downloads' {
            $mine = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4)
            $copy = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5) -Name 'disk-cleanup-selection (1).json'
            [System.IO.File]::SetLastWriteTimeUtc($copy, [System.DateTime]::UtcNow.AddMinutes(-10))
            $foreign = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:otherToken -Ids @(4) -Name 'disk-cleanup-selection (2).json'
            $broken = Add-RawSelection -Sandbox $script:sandbox -Content ('zqnot a selection ' + $script:token) -Name 'disk-cleanup-selection (3).json'
            $lookalike = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(4) -Name 'zqdisk-cleanup-selection.json'
            $downloadsBefore = @([System.IO.Directory]::GetFiles($script:sandbox.Downloads)).Count

            $run = Invoke-Apply -Token $script:token

            $run.Data.trashed_count | Should -Be 1
            Test-Path -LiteralPath $mine | Should -BeFalse
            Test-Path -LiteralPath $copy | Should -BeFalse
            Test-Path -LiteralPath $foreign | Should -BeTrue
            Test-Path -LiteralPath $broken | Should -BeTrue
            Test-Path -LiteralPath $lookalike | Should -BeTrue
            Test-Path -LiteralPath $script:files.OldNotes | Should -BeTrue
            @([System.IO.Directory]::GetFiles($script:sandbox.Downloads)).Count | Should -Be ($downloadsBefore - 3)
        }

        It 'reports TOKEN_INVALID for another token and moves nothing' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:otherToken -Ids @(1)

            $run = Invoke-Apply -Token $script:otherToken

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeTrue
        }

        It 'reports TOKEN_INVALID for the token of a review that was replaced by a newer one' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            $newToken = Invoke-ReviewForToken

            $run = Invoke-Apply -Token $script:token

            $newToken | Should -Not -Be $script:token
            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
        }

        It 'reports TOKEN_EXPIRED after 60 minutes and moves nothing' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3600))

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 1
            $run.Data.error.code | Should -Be 'TOKEN_EXPIRED'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $script:files.Holiday | Should -BeTrue
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeFalse
            Test-Path -LiteralPath $script:sandbox.Report | Should -BeFalse
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
        }

        It 'reports TOKEN_INVALID, not TOKEN_EXPIRED, for another token once the review has expired' {
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3600))

            $run = Invoke-Apply -Token $script:otherToken

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Test-Path -LiteralPath $script:sandbox.Manifest | Should -BeFalse
        }

        It 'still accepts the token after 59 minutes' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(5)
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) - 3540))

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
        }

        It 'rejects a manifest dated in the future' {
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)
            Set-SandboxManifestEpoch -Manifest $script:sandbox.Manifest -Replacement ([string]((Get-EpochNow) + 600))

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'TOKEN_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
        }

        It 'burns the token before anything is moved' {
            Mock Send-FileToRecycleBin {
                $script:manifestSeenDuringMove = [System.IO.File]::Exists($script:sandbox.Manifest)
                'failed'
            }
            $script:manifestSeenDuringMove = $true
            $null = Add-SandboxSelection -Sandbox $script:sandbox -Token $script:token -Ids @(1)

            $null = Invoke-Apply -Token $script:token

            $script:manifestSeenDuringMove | Should -BeFalse
        }
    }
}

Describe 'Read-SelectionFile' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        [void][System.IO.Directory]::CreateDirectory($script:sandbox.Downloads)
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'returns the token and the distinct ids in order' {
        $path = Add-RawSelection -Sandbox $script:sandbox -Content '{"token":"0a1b2c3d","secret":"00112233445566778899aabbccddeeff","ids":[9,1,5,1,09]}'

        $selection = Read-SelectionFile -File (New-Object -TypeName System.IO.FileInfo -ArgumentList $path)

        $selection.Token | Should -BeExactly '0a1b2c3d'
        $selection.Secret | Should -BeExactly '00112233445566778899aabbccddeeff'
        ($selection.Ids -join ',') | Should -Be '9,1,5'
    }

    It 'returns nothing for a selection without a secret' {
        $path = Add-RawSelection -Sandbox $script:sandbox -Content '{"token":"0a1b2c3d","ids":[9,1,5]}'

        Read-SelectionFile -File (New-Object -TypeName System.IO.FileInfo -ArgumentList $path) | Should -BeNullOrEmpty
    }

    It 'returns nothing for a file that cannot be read' {
        $missing = Join-Path -Path $script:sandbox.Downloads -ChildPath 'disk-cleanup-selection.json'

        Read-SelectionFile -File (New-Object -TypeName System.IO.FileInfo -ArgumentList $missing) | Should -BeNullOrEmpty
    }

    It 'matches selection file names exactly: <Name> is <Expected>' -ForEach @(
        @{ Name = 'disk-cleanup-selection.json'; Expected = $true }
        @{ Name = 'disk-cleanup-selection (1).json'; Expected = $true }
        @{ Name = 'disk-cleanup-selection (999).json'; Expected = $true }
        @{ Name = 'disk-cleanup-selection-12.json'; Expected = $true }
        @{ Name = 'disk-cleanup-selection 7.json'; Expected = $true }
        @{ Name = 'disk-cleanup-selection 1234.json'; Expected = $false }
        @{ Name = 'disk-cleanup-selection 7 .json'; Expected = $false }
        @{ Name = 'disk-cleanup-selection (1).json '; Expected = $false }
        @{ Name = 'disk-cleanup-selection  (1).json'; Expected = $false }
        @{ Name = 'disk-cleanup-selection-.json'; Expected = $false }
        @{ Name = 'disk-cleanup-selection.json.exe'; Expected = $false }
        @{ Name = '..\disk-cleanup-selection.json'; Expected = $false }
        @{ Name = ''; Expected = $false }
    ) {
        Test-SelectionFileName -Name $Name | Should -Be $Expected
    }
}
