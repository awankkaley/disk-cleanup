BeforeAll {
    $script:scriptRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\scripts'
    $script:entryScript = Join-Path -Path $script:scriptRoot -ChildPath 'cleanup.ps1'
    $script:sourceFiles = @([System.IO.Directory]::GetFiles($script:scriptRoot, '*.ps1', [System.IO.SearchOption]::AllDirectories))
    $script:maxFileLines = 800
    $script:maxFunctionLines = 50

    function Get-SourceMatchList {
        param([string]$Pattern)
        foreach ($file in $script:sourceFiles) {
            $number = 0
            foreach ($line in [System.IO.File]::ReadAllLines($file)) {
                $number += 1
                if ($line.TrimStart().StartsWith('#')) { continue }
                if ($line -match $Pattern) { ([System.IO.Path]::GetFileName($file) + ':' + $number) }
            }
        }
    }

    function Get-SourceLineList {
        param([string]$Pattern)
        foreach ($file in $script:sourceFiles) {
            foreach ($line in [System.IO.File]::ReadAllLines($file)) {
                if ($line.TrimStart().StartsWith('#')) { continue }
                if ($line -match $Pattern) { $line }
            }
        }
    }
}

Describe 'source rules' {
    BeforeEach {
        Set-StrictMode -Version Latest
    }

    It 'finds the script and its libraries' {
        $script:sourceFiles.Count | Should -BeGreaterThan 1
        Test-Path -LiteralPath $script:entryScript | Should -BeTrue
    }

    It 'parses without syntax errors in this PowerShell version' {
        $problems = @(foreach ($file in $script:sourceFiles) {
                $tokens = $null
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
                foreach ($parseError in @($errors)) {
                    [System.IO.Path]::GetFileName($file) + ': ' + $parseError.Message
                }
            })

        ($problems -join '; ') | Should -BeNullOrEmpty
    }

    It 'is ASCII only, because Windows PowerShell 5.1 misreads UTF-8 without a BOM' {
        $offenders = @(foreach ($file in $script:sourceFiles) {
                $highBytes = @([System.IO.File]::ReadAllBytes($file) | Where-Object { $_ -gt 127 })
                if ($highBytes.Count -gt 0) { [System.IO.Path]::GetFileName($file) }
            })

        ($offenders -join ', ') | Should -BeNullOrEmpty
    }

    It 'keeps every file under 800 lines and every function under 50 lines' {
        $offenders = @(foreach ($file in $script:sourceFiles) {
                $name = [System.IO.Path]::GetFileName($file)
                if (@([System.IO.File]::ReadAllLines($file)).Count -ge $script:maxFileLines) { $name }
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
                $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
                foreach ($definition in $definitions) {
                    $length = $definition.Extent.EndLineNumber - $definition.Extent.StartLineNumber + 1
                    if ($length -ge $script:maxFunctionLines) { $name + ':' + $definition.Name }
                }
            })

        ($offenders -join ', ') | Should -BeNullOrEmpty
    }

    It 'removes files in exactly one place' {
        (@(Get-SourceMatchList -Pattern 'Remove-Item|\brm\b|\bdel\b|\berase\b|\brmdir\b') -join ', ') | Should -BeNullOrEmpty
        $deleteCalls = @(Get-SourceMatchList -Pattern '\.Delete\(|::Delete\(|DeleteDirectory|DeletePermanently')
        $deleteCalls.Count | Should -Be 1
        $deleteCalls[0] | Should -Match '^FileSystem\.ps1:'
    }

    It 'moves personal files in exactly one place, and only to the Recycle Bin' {
        $trashCalls = @(Get-SourceMatchList -Pattern 'DeleteFile|SendToRecycleBin|RecycleOption|SHFileOperation')
        $trashCalls.Count | Should -Be 1
        $trashCalls[0] | Should -Match '^Platform\.ps1:'
        $line = @(Get-SourceLineList -Pattern 'DeleteFile')[0]
        $line | Should -MatchExactly '::DeleteFile\(\$Path, ''OnlyErrorDialogs'', ''SendToRecycleBin''\)'
        $moves = '\.MoveTo\(|::Move\(|Move-Item|Rename-Item|\.CopyTo\(|::Copy\(|Copy-Item|File\]::Replace\(|MoveFile|CopyFile'
        (@(Get-SourceMatchList -Pattern $moves) -join ', ') | Should -BeNullOrEmpty
        @(Get-SourceMatchList -Pattern 'Send-FileToRecycleBin').Count | Should -Be 2
    }

    It 'opens nothing but the review report, and never with a verb' {
        $shellCalls = @(Get-SourceMatchList -Pattern 'UseShellExecute\s*=\s*\$true|Invoke-Item|ShellExecute\(|explorer\.exe')
        $shellCalls.Count | Should -Be 1
        $shellCalls[0] | Should -Match '^Platform\.ps1:'
        (@(Get-SourceMatchList -Pattern '\.Verb\b') -join ', ') | Should -BeNullOrEmpty
        @(Get-SourceMatchList -Pattern 'Open-ReviewReport').Count | Should -Be 2
    }

    It 'never parses the selection file as JSON and never evaluates text' {
        (@(Get-SourceMatchList -Pattern 'Invoke-Expression|\biex\b|ScriptBlock\]::Create|Import-Clixml') -join ', ') | Should -BeNullOrEmpty
        $jsonCalls = @(Get-SourceMatchList -Pattern 'ConvertFrom-Json')
        $jsonCalls.Count | Should -Be 1
        $jsonCalls[0] | Should -Match '^Options\.ps1:'
    }

    It 'lets the test seams only switch work off' {
        $seams = @(Get-SourceLineList -Pattern 'env:DISK_CLEANUP_')
        $seams.Count | Should -Be 2
        foreach ($seam in $seams) {
            $seam.Trim() | Should -MatchExactly '^if \(\$env:DISK_CLEANUP_SKIP_[A-Z_]+ -eq \$script:SKIP_SEAM_VALUE\) \{ return (\$false|\$script:RECYCLE_FAILED) \}$'
        }
    }

    It 'never elevates, kills processes, changes permissions or goes online' {
        $pattern = 'sudo|runas|RunAs|Start-Process|Stop-Process|taskkill|icacls|takeown|Set-Acl|Invoke-WebRequest|Invoke-RestMethod|Net\.WebClient'

        (@(Get-SourceMatchList -Pattern $pattern) -join ', ') | Should -BeNullOrEmpty
    }

    It 'terminates nothing but its own timed-out child process' {
        (@(Get-SourceMatchList -Pattern 'Get-Process[^|]*\|.*Kill|\.CloseMainWindow\(|\.Terminate\(') -join ', ') | Should -BeNullOrEmpty
        $killCalls = @(Get-SourceMatchList -Pattern '\.Kill\(')
        $killCalls.Count | Should -Be 1
        $killCalls[0] | Should -Match '^Platform\.ps1:'
    }

    It 'never changes the working directory of the caller' {
        (@(Get-SourceMatchList -Pattern 'Set-Location|Push-Location|\bcd\b|\bchdir\b|CurrentDirectory') -join ', ') | Should -BeNullOrEmpty
    }

    It 'never writes to the host or leaves debug output behind' {
        (@(Get-SourceMatchList -Pattern 'Write-Host|Write-Debug|Write-Verbose|Write-Warning|\[Console\]') -join ', ') | Should -BeNullOrEmpty
    }

    It 'only prunes dangling docker images' {
        . $script:entryScript

        ($script:DOCKER_PRUNE_ARGUMENTS -join ' ') | Should -Be 'image prune --force'
    }
}

Describe 'category catalog' {
    BeforeAll {
        . $script:entryScript
    }

    BeforeEach {
        Set-StrictMode -Version Latest
    }

    It 'gives every category a handler and static, separator-free text' {
        foreach ($category in $script:CATEGORIES) {
            @('directory', 'tool', 'docker', 'trash', 'node-modules') | Should -Contain $category['Kind']
            $category['Label'] | Should -Not -Match '[\\/]'
            $category['Impact'] | Should -Not -Match '[\\/]'
            $category['Id'] | Should -MatchExactly '^[a-z]+(-[a-z]+)*$'
        }
    }

    It 'has a tool or directory definition for every table-driven category' {
        foreach ($category in $script:CATEGORIES) {
            if ($category['Kind'] -eq 'tool') { $script:TOOL_CATEGORIES.ContainsKey($category['Id']) | Should -BeTrue }
        }
        foreach ($id in @('temp-files', 'crash-dumps', 'thumbnail-cache', 'gradle-cache', 'cargo-cache')) {
            $script:SIMPLE_DIRECTORY_CATEGORIES.ContainsKey($id) | Should -BeTrue
        }
    }

    It 'marks only safe categories as recommended and only trash as flag-gated' {
        foreach ($category in $script:CATEGORIES) {
            if ($category['Id'] -eq 'trash') {
                $category['Risk'] | Should -Be 'irreversible'
                $category['RequiresFlag'] | Should -Be '--empty-trash'
            } else {
                $category['RequiresFlag'] | Should -BeNullOrEmpty
            }
        }
    }

    It 'gives every category a rebuild cost of 1, 2 or 3' {
        foreach ($category in $script:CATEGORIES) {
            $category['RebuildCost'] | Should -BeOfType [int]
            @(1, 2, 3) | Should -Contain $category['RebuildCost']
        }
    }

    It 'knows only the apps whose cache layout was checked, by cache folder only' {
        $names = @($script:KNOWN_APP_CACHES | ForEach-Object { $_['Name'] })
        ($names -join ',') | Should -BeExactly 'Slack,Discord,Microsoft Teams,Visual Studio Code'
        ($script:APP_CACHE_DIR_NAMES -join ',') | Should -BeExactly 'Cache,Code Cache,GPUCache,CachedData'
        foreach ($app in $script:KNOWN_APP_CACHES) {
            $app['Path'] | Should -Not -Match '^[\\/]|\.\.|:'
            @($app['Processes']).Count | Should -BeGreaterThan 0
        }
    }

    It 'never touches the folders of Spotify, WhatsApp, Telegram or Zoom' {
        $catalog = [System.IO.File]::ReadAllText((Join-Path -Path $script:scriptRoot -ChildPath 'lib\Catalog.ps1'))

        $catalog | Should -Not -Match '(?i)spotify|whatsapp|telegram|zoom|tdata|PersistentCache'
        foreach ($app in $script:KNOWN_APP_CACHES) {
            (@($app['Name'], $app['Path']) + @($app['Processes'])) -join ' ' | Should -Not -Match '(?i)spotify|whatsapp|telegram|zoom'
        }
    }

    It 'gives every category the rebuild cost shared with macOS' {
        $expected = @{
            'temp-files' = 1; 'crash-dumps' = 1; 'thumbnail-cache' = 1; 'browser-chrome' = 1; 'browser-edge' = 1
            'browser-firefox' = 1; 'browser-brave' = 1; 'browser-opera' = 1; 'browser-arc' = 1
            'app-caches' = 2; 'store-app-caches' = 2; 'npm-cache' = 2; 'yarn-cache' = 2; 'pnpm-store' = 2
            'pip-cache' = 2; 'go-cache' = 2; 'docker-dangling' = 2; 'trash' = 2
            'gradle-cache' = 3; 'cargo-cache' = 3; 'node-modules-stale' = 3
        }
        $script:CATEGORIES.Count | Should -Be $expected.Count
        foreach ($category in $script:CATEGORIES) {
            $category['RebuildCost'] | Should -Be $expected[$category['Id']]
        }
        $script:BYTES_PER_GIGABYTE | Should -Be 1073741824
    }

    It 'creates the selection secret in one place and never hands it to the output document' {
        @(Get-SourceMatchList -Pattern 'Get-FreshSecret').Count | Should -Be 2
        @(Get-SourceMatchList -Pattern 'RandomNumberGenerator').Count | Should -Be 1
        $documentLines = @(Get-SourceLineList -Pattern 'Get-ReviewDocument|Get-ReviewApplyDocument|Get-ErrorDocument')
        ($documentLines -join ' ') | Should -Not -Match '(?i)secret'
    }

    It 'limits every known app and browser to cache folder names' {
        $allowed = @('Cache', 'Code Cache', 'GPUCache', 'CachedData', 'cache2', 'startupCache')
        foreach ($name in $script:APP_CACHE_DIR_NAMES) { $allowed | Should -Contain $name }
        foreach ($browser in $script:BROWSERS) {
            foreach ($name in $browser['CacheNames']) { $allowed | Should -Contain $name }
        }
        foreach ($app in $script:KNOWN_APP_CACHES) {
            foreach ($key in @('Name', 'Base', 'Path', 'Processes')) { $app.ContainsKey($key) | Should -BeTrue }
            @('Home', 'Local', 'Roaming') | Should -Contain $app['Base']
        }
    }

    It 'uses exactly the canonical result error codes shared with macOS' {
        $expected = @{
            cleaned = ''; skipped_running = 'APP_RUNNING'; skipped_no_permission = 'PERMISSION_DENIED'
            partial = 'SOME_ITEMS_REMAIN'; not_found = 'NOT_FOUND'; unavailable = 'TOOL_UNAVAILABLE'; failed = 'INTERNAL'
        }
        foreach ($status in $expected.Keys) {
            [string](Get-CleanState -Status $status).ErrorCode | Should -BeExactly $expected[$status]
        }
        (Get-CleanState -Status 'unavailable' -ErrorCode 'CUSTOM_LOCATION').ErrorCode | Should -BeExactly 'CUSTOM_LOCATION'
        (Get-DeleteState -FreedBytes 5 -Deleted 1 -Failed 0 -Refused 0).Status | Should -Be 'cleaned'
        (Get-DeleteState -FreedBytes 0 -Deleted 0 -Failed 0 -Refused 0).ErrorCode | Should -BeExactly 'NOT_FOUND'
        (Get-DeleteState -FreedBytes 5 -Deleted 1 -Failed 1 -Refused 0).ErrorCode | Should -BeExactly 'SOME_ITEMS_REMAIN'
        (Get-DeleteState -FreedBytes 0 -Deleted 0 -Failed 1 -Refused 0).ErrorCode | Should -BeExactly 'PERMISSION_DENIED'
        (Get-DeleteState -FreedBytes 0 -Deleted 0 -Failed 0 -Refused 1).ErrorCode | Should -BeExactly 'GUARD_REFUSED'
        $known = @(
            'APP_RUNNING', 'PERMISSION_DENIED', 'SOME_ITEMS_REMAIN', 'NOT_FOUND', 'TOOL_UNAVAILABLE', 'CUSTOM_LOCATION',
            'TOOL_FAILED', 'GUARD_REFUSED', 'INTERNAL'
        )
        $pattern = "-ErrorCode '([A-Z_]+)'"
        foreach ($file in $script:sourceFiles) {
            foreach ($found in [regex]::Matches([System.IO.File]::ReadAllText($file), $pattern)) {
                $known | Should -Contain $found.Groups[1].Value
            }
        }
    }

    It 'never treats LocalCache of a Store app as cache' {
        ($script:STORE_APP_CACHE_SUBPATHS -join ',') | Should -Be 'TempState,AC\INetCache'
    }

    It 'defines a default location, a fallback rule and a size rule for every tool cache' {
        foreach ($id in $script:TOOL_CATEGORIES.Keys) {
            $spec = $script:TOOL_CATEGORIES[$id]
            foreach ($key in @('Tool', 'DirArguments', 'CleanArguments', 'DefaultBase', 'DefaultPath', 'SubPath', 'FallbackDelete', 'SizeUnknown')) {
                $spec.ContainsKey($key) | Should -BeTrue
            }
            $spec['DefaultPath'] | Should -Not -BeNullOrEmpty
        }
        $script:TOOL_CATEGORIES['pnpm-store']['SizeUnknown'] | Should -BeTrue
        $script:TOOL_CATEGORIES['pnpm-store']['FallbackDelete'] | Should -BeFalse
    }

    It 'quotes tool arguments only when needed and routes batch shims through cmd.exe' {
        ConvertTo-ToolArgument -Value 'cache' | Should -BeExactly 'cache'
        ConvertTo-ToolArgument -Value 'two words' | Should -BeExactly '"two words"'
        $batch = Get-ToolStartInfo -Path 'C:\zqtools\npm.cmd' -Arguments @('cache', 'clean', '--force') -WorkingDirectory 'C:\zqstate'
        $batch.FileName | Should -Match 'cmd\.exe$'
        $batch.Arguments | Should -BeExactly '/d /s /c ""C:\zqtools\npm.cmd" cache clean --force"'
        $direct = Get-ToolStartInfo -Path 'C:\zqtools\go.exe' -Arguments @('env', 'GOCACHE') -WorkingDirectory 'C:\zqstate'
        $direct.FileName | Should -BeExactly 'C:\zqtools\go.exe'
        $direct.Arguments | Should -BeExactly 'env GOCACHE'
        $direct.WorkingDirectory | Should -BeExactly 'C:\zqstate'
        $direct.RedirectStandardInput | Should -BeTrue
        $direct.RedirectStandardError | Should -BeTrue
        $direct.UseShellExecute | Should -BeFalse
    }

    It 'has a static message for every error code' {
        $codes = @(
            'USAGE', 'UNKNOWN_CATEGORY', 'TOKEN_MISSING', 'TOKEN_INVALID', 'TOKEN_EXPIRED', 'CATEGORY_NOT_IN_SCAN',
            'TRASH_FLAG_REQUIRED', 'DEEP_SCAN_REQUIRED', 'INVALID_ARGUMENT', 'UNSUPPORTED_PLATFORM', 'INTERNAL',
            'SELECTION_NOT_FOUND', 'SELECTION_INVALID', 'SELECTION_NO_PERMISSION'
        )
        $script:ERROR_MESSAGES.Count | Should -Be $codes.Count
        foreach ($code in $codes) {
            $script:ERROR_MESSAGES[$code] | Should -Not -BeNullOrEmpty
            $script:ERROR_MESSAGES[$code] | Should -Not -Match '[\\/]'
        }
        Get-FailureCode -Message 'anything unexpected' | Should -Be 'INTERNAL'
        Get-ExitCode -Code 'USAGE' | Should -Be 2
        Get-ExitCode -Code 'TOKEN_EXPIRED' | Should -Be 1
    }

    It 'parses the reclaimed space that docker reports: <Line>' -ForEach @(
        @{ Line = 'Total reclaimed space: 0B'; Expected = 0 }
        @{ Line = 'Total reclaimed space: 512B'; Expected = 512 }
        @{ Line = 'Total reclaimed space: 1.5kB'; Expected = 1500 }
        @{ Line = 'Total reclaimed space: 2.25MB'; Expected = 2250000 }
        @{ Line = 'Total reclaimed space: 3GB'; Expected = 3000000000 }
        @{ Line = 'nothing useful'; Expected = 0 }
    ) {
        ConvertFrom-DockerReclaimed -Lines @('Deleted Images:', $Line) | Should -Be $Expected
    }
}

Describe 'direct invocation' {
    BeforeAll {
        $script:powershellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    }

    BeforeEach {
        Set-StrictMode -Version Latest
    }

    It 'prints one JSON line and exits 0 for --version' {
        if (-not (Test-Path -LiteralPath $script:powershellExe)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $output = @(& $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $script:entryScript --version)

        $LASTEXITCODE | Should -Be 0
        $output.Count | Should -Be 1
        (ConvertFrom-Json -InputObject ([string]$output[0])).command | Should -Be 'version'
    }

    It 'prints a JSON usage error and exits 2 without a command' {
        if (-not (Test-Path -LiteralPath $script:powershellExe)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }

        $output = @(& $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $script:entryScript)

        $LASTEXITCODE | Should -Be 2
        $output.Count | Should -Be 1
        (ConvertFrom-Json -InputObject ([string]$output[0])).error.code | Should -Be 'USAGE'
    }

    It 'exits 1 with a JSON error for a clean without a matching scan' {
        if (-not (Test-Path -LiteralPath $script:powershellExe)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not available here'
            return
        }
        $arguments = @('clean', '--token', 'not-a-token', '--categories', 'temp-files,crash-dumps')

        $output = @(& $script:powershellExe -NoProfile -ExecutionPolicy Bypass -File $script:entryScript @arguments)

        $LASTEXITCODE | Should -Be 1
        (ConvertFrom-Json -InputObject ([string]$output[0])).error.code | Should -Be 'TOKEN_INVALID'
    }
}
