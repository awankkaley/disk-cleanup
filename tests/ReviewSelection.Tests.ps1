BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    function Invoke-Apply {
        param([string]$Token)
        return (Invoke-CleanupJson -Arguments @('review-apply', '--token', $Token))
    }

    function Add-RawSelection {
        param($Sandbox, [string]$Content, [string]$Name = 'disk-cleanup-selection.json')
        $path = Join-Path -Path $Sandbox.Downloads -ChildPath $Name
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

    Context 'rejecting a selection' {
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
            $big = Add-RawSelection -Sandbox $script:sandbox -Content ('{"token":"' + $script:token + '","ids":[1]}' + $padding)

            $run = Invoke-Apply -Token $script:token

            $run.Data.error.code | Should -Be 'SELECTION_INVALID'
            Should -Invoke Send-FileToRecycleBin -Times 0 -Exactly
            Test-Path -LiteralPath $big | Should -BeTrue
        }

        It 'accepts a selection of exactly 1 MB' {
            $prefix = '{"token":"' + $script:token + '","ids":[5]}'
            $padding = New-Object -TypeName string -ArgumentList ([char]32), (1048576 - $prefix.Length)
            $null = Add-RawSelection -Sandbox $script:sandbox -Content ($prefix + $padding)

            $run = Invoke-Apply -Token $script:token

            $run.ExitCode | Should -Be 0
            $run.Data.trashed_count | Should -Be 1
        }

        It 'rejects malformed content: <Name>' -ForEach @(
            @{ Name = 'empty file'; Template = '' }
            @{ Name = 'trailing comma'; Template = '{"token":"TOKEN","ids":[1,]}' }
            @{ Name = 'keys in another order'; Template = '{"ids":[1],"token":"TOKEN"}' }
            @{ Name = 'an extra key'; Template = '{"token":"TOKEN","ids":[1],"all":true}' }
            @{ Name = 'text after the document'; Template = '{"token":"TOKEN","ids":[1]} $(calc)' }
            @{ Name = 'text before the document'; Template = 'x{"token":"TOKEN","ids":[1]}' }
            @{ Name = 'a second document'; Template = '{"token":"TOKEN","ids":[1]}{"token":"TOKEN","ids":[2]}' }
            @{ Name = 'ids as strings'; Template = '{"token":"TOKEN","ids":["1"]}' }
            @{ Name = 'a negative id'; Template = '{"token":"TOKEN","ids":[-1]}' }
            @{ Name = 'a fractional id'; Template = '{"token":"TOKEN","ids":[1.5]}' }
            @{ Name = 'an exponent'; Template = '{"token":"TOKEN","ids":[1e3]}' }
            @{ Name = 'an id of seven digits'; Template = '{"token":"TOKEN","ids":[1234567]}' }
            @{ Name = 'a path instead of an id'; Template = '{"token":"TOKEN","ids":["C:\\Users"]}' }
            @{ Name = 'ids not in an array'; Template = '{"token":"TOKEN","ids":1}' }
            @{ Name = 'single quotes'; Template = '{''token'':''TOKEN'',''ids'':[1]}' }
            @{ Name = 'an upper-case token'; Template = '{"token":"ABCDEF12","ids":[1]}' }
            @{ Name = 'a token with a space'; Template = '{"token":"TOKEN ","ids":[1]}' }
            @{ Name = 'a bare array'; Template = '[1,2,3]' }
            @{ Name = 'PowerShell code'; Template = '$(throw "zqevaluated"); {"token":"TOKEN","ids":[1]}' }
            @{ Name = 'an escaped key'; Template = '{"\u0074oken":"TOKEN","ids":[1]}' }
        ) {
            $bad = Add-RawSelection -Sandbox $script:sandbox -Content $Template.Replace('TOKEN', $script:token)

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
            Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
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
        $path = Add-RawSelection -Sandbox $script:sandbox -Content '{"token":"0a1b2c3d","ids":[9,1,5,1,09]}'

        $selection = Read-SelectionFile -File (New-Object -TypeName System.IO.FileInfo -ArgumentList $path)

        $selection.Token | Should -BeExactly '0a1b2c3d'
        ($selection.Ids -join ',') | Should -Be '9,1,5'
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
