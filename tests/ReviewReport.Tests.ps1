BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\cleanup.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Sandbox.Helpers.ps1')

    $script:fakeHome = 'C:\Users\zqowner'
    $script:fakeSecret = '00112233445566778899aabbccddeeff'
    $script:csp = '<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; script-src ''unsafe-inline''">'

    function Get-FakeItem {
        param([int]$Id, [string]$Name, [string]$Folder = 'Videos', [long]$Size = 12582912, [string]$Group = 'large-files')
        return [pscustomobject]@{
            Id         = $Id
            Path       = ($script:fakeHome + '\' + $Folder + '\' + $Name)
            Size       = $Size
            Length     = $Size
            MtimeTicks = (New-Object -TypeName System.DateTime -ArgumentList 2024, 3, 9, 12, 0, 0, ([System.DateTimeKind]::Utc)).Ticks
            Group      = $Group
        }
    }

    function Get-ScriptBlockText {
        param([string]$Html)
        $start = $Html.IndexOf('<script>')
        $end = $Html.LastIndexOf('</script>')
        return $Html.Substring($start, $end - $start)
    }
}

Describe 'ConvertTo-HtmlText' {
    BeforeEach {
        Set-StrictMode -Version Latest
    }

    It 'escapes <Name>' -ForEach @(
        @{ Name = 'an ampersand'; Text = 'a&b'; Expected = 'a&amp;b' }
        @{ Name = 'angle brackets'; Text = '<b>'; Expected = '&lt;b&gt;' }
        @{ Name = 'a double quote'; Text = 'say "hi"'; Expected = 'say &quot;hi&quot;' }
        @{ Name = 'a single quote'; Text = "it's"; Expected = 'it&#39;s' }
        @{ Name = 'an existing entity, once more'; Text = '&lt;'; Expected = '&amp;lt;' }
        @{ Name = 'an image payload'; Text = '<img src=x onerror=alert(1)>'; Expected = '&lt;img src=x onerror=alert(1)&gt;' }
        @{ Name = 'a script end tag'; Text = '</script><script>alert(1)</script>'; Expected = '&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;' }
        @{ Name = 'an attribute breakout'; Text = '" onmouseover="alert(1)'; Expected = '&quot; onmouseover=&quot;alert(1)' }
        @{ Name = 'a single-quote breakout'; Text = "' onfocus='alert(1)"; Expected = '&#39; onfocus=&#39;alert(1)' }
        @{ Name = 'nothing in plain text'; Text = 'zq holiday (1) $(calc) `x` [1] %TEMP%.mp4'; Expected = 'zq holiday (1) $(calc) `x` [1] %TEMP%.mp4' }
        @{ Name = 'an empty string'; Text = ''; Expected = '' }
    ) {
        ConvertTo-HtmlText -Text $Text | Should -BeExactly $Expected
    }

    It 'leaves none of the five special characters behind' {
        $escaped = ConvertTo-HtmlText -Text '<>"''&<>"''&'

        $escaped | Should -Not -Match '[<>"'']'
        ($escaped -replace '&(amp|lt|gt|quot|#39);', '') | Should -BeExactly ''
    }
}

Describe 'review report' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:hostile = @(
            (Get-FakeItem -Id 1 -Name '<img src=x onerror=alert(1)>.mp4'),
            (Get-FakeItem -Id 2 -Name '</script><script>alert(2)</script>.zip' -Folder '<b>zqbold</b>'),
            (Get-FakeItem -Id 3 -Name '" autofocus onfocus="alert(3).iso' -Folder 'zq"quoted'),
            (Get-FakeItem -Id 4 -Name "zq' onclick='alert(4).txt" -Size 300 -Group 'old-downloads' -Folder 'Downloads'),
            (Get-FakeItem -Id 5 -Name 'zq&amp;-->]]>${alert(5)}`.bin' -Size 200 -Group 'old-downloads' -Folder 'Downloads')
        )
        $script:html = Get-ReviewReportHtml -Token 'a1b2c3d4' -Secret $script:fakeSecret -Items $script:hostile -HomeRoot $script:fakeHome
    }

    It 'carries the content security policy and loads nothing from anywhere' {
        $script:html.Contains($script:csp) | Should -BeTrue
        $script:html | Should -Not -Match 'https?:'
        $script:html | Should -Not -Match '(?i)\b(src|href|action|srcset|poster|data)\s*=\s*["''][^"'']'
        $script:html | Should -Not -Match '(?i)<(link|iframe|img|object|embed|form|base|frame|video|audio|source)\b'
        $script:html | Should -Not -Match '@import|//[a-z]'
        $script:html | Should -Not -MatchExactly 'url\('
        $script:html | Should -Not -Match '(?i)fetch\(|XMLHttpRequest|WebSocket|sendBeacon|importScripts|eval\(|innerHTML|document\.write'
    }

    It 'is one self-contained page with a single style block and a single script block' {
        $script:html | Should -Match '^<!DOCTYPE html>'
        ([regex]::Matches($script:html, '<script')).Count | Should -Be 1
        ([regex]::Matches($script:html, '</script>')).Count | Should -Be 1
        ([regex]::Matches($script:html, '<style')).Count | Should -Be 1
        ([regex]::Matches($script:html, '</html>')).Count | Should -Be 1
    }

    It 'renders hostile names as text, never as markup' {
        $script:html | Should -Not -Match '<img'
        $script:html | Should -Not -Match 'onerror=alert\(1\)>'
        $script:html.Contains('&lt;img src=x onerror=alert(1)&gt;.mp4') | Should -BeTrue
        $script:html.Contains('&lt;/script&gt;&lt;script&gt;alert(2)&lt;/script&gt;.zip') | Should -BeTrue
        $script:html.Contains('~\&lt;b&gt;zqbold&lt;/b&gt;') | Should -BeTrue
        $script:html.Contains('&quot; autofocus onfocus=&quot;alert(3).iso') | Should -BeTrue
        $script:html.Contains('zq&#39; onclick=&#39;alert(4).txt') | Should -BeTrue
        $script:html.Contains('zq&amp;amp;--&gt;]]&gt;${alert(5)}`.bin') | Should -BeTrue
    }

    It 'keeps every row a row: no item text can open a tag or an attribute' {
        $rows = @($script:html -split "`n" | Where-Object { $_.StartsWith('<tr data-id=') })

        $rows.Count | Should -Be 5
        foreach ($row in $rows) {
            ([regex]::Matches($row, '<tr ')).Count | Should -Be 1
            ([regex]::Matches($row, '<td')).Count | Should -Be 6
            ([regex]::Matches($row, '<input ')).Count | Should -Be 1
            ([regex]::Matches($row, '<')).Count | Should -Be 17
            ([regex]::Matches($row, '"')).Count | Should -Be 28
            ([regex]::Matches($row, ' dir="auto"')).Count | Should -Be 2
            $row | Should -Not -Match "'"
            $row | Should -MatchExactly '^<tr data-id="[0-9]+" data-size="[0-9]+" data-group="(large-files|old-downloads)"><td><input type="checkbox" id="pick[0-9]+"></td>'
        }
    }

    It 'never puts item data into the script block' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText | Should -Not -Match 'zq'
        $scriptText | Should -Not -Match 'alert'
        $scriptText | Should -Not -Match 'a1b2c3d4'
        $scriptText | Should -Not -Match $script:fakeSecret
        $script:html.IndexOf('<tr data-id=') | Should -BeLessThan $script:html.IndexOf('<script>')
        $script:html.LastIndexOf('<tr data-id=') | Should -BeLessThan $script:html.IndexOf('<script>')
    }

    It 'shows each item unchecked with its size, date, group and a folder relative to the profile' {
        $plain = Get-ReviewReportHtml -Token 'a1b2c3d4' -Secret $script:fakeSecret -HomeRoot $script:fakeHome -Items @(
            (Get-FakeItem -Id 7 -Name 'zqholiday.mp4' -Folder 'Videos\zqtrip'),
            (Get-FakeItem -Id 8 -Name 'zqold.exe' -Folder 'Downloads' -Size 300 -Group 'old-downloads')
        )

        $plain | Should -Not -Match '(?i)\schecked'
        $plain.Contains('<tr data-id="7" data-size="12582912" data-group="large-files">') | Should -BeTrue
        $plain.Contains('<td class="name" dir="auto"><label for="pick7">zqholiday.mp4</label></td>') | Should -BeTrue
        $plain.Contains('<td class="folder" dir="auto">~\Videos\zqtrip</td>') | Should -BeTrue
        $plain.Contains('<td class="num">12.0 MB</td>') | Should -BeTrue
        $plain | Should -Match '<td class="when">2024-03-(08|09|10)</td>'
        $plain.Contains('<td class="group" data-t="gLarge">Large files</td></tr>') | Should -BeTrue
        $plain.Contains('<td class="group" data-t="gOld">Old items in Downloads</td></tr>') | Should -BeTrue
        $plain.Contains('<td class="num">300 B</td>') | Should -BeTrue
        $plain | Should -Not -Match ([regex]::Escape($script:fakeHome))
    }

    It 'embeds the token once, as an attribute, and refuses a malformed token' {
        ([regex]::Matches($script:html, 'a1b2c3d4')).Count | Should -Be 1
        $script:html.Contains('<body data-token="a1b2c3d4" data-secret="00112233445566778899aabbccddeeff">') | Should -BeTrue
        { Get-ReviewReportHtml -Token '"><script>' -Secret $script:fakeSecret -Items @() -HomeRoot $script:fakeHome } | Should -Throw
        { Get-ReviewReportHtml -Token 'A1B2C3D4' -Secret $script:fakeSecret -Items @() -HomeRoot $script:fakeHome } | Should -Throw
    }

    It 'embeds the selection secret once, next to the token, and refuses a malformed secret' {
        ([regex]::Matches($script:html, $script:fakeSecret)).Count | Should -Be 1
        foreach ($bad in @('', 'a1b2c3d4', '00112233445566778899AABBCCDDEEFF', '00112233445566778899aabbccddeef', '"><script>alert(1)</script>000000')) {
            { Get-ReviewReportHtml -Token 'a1b2c3d4' -Secret $bad -Items @() -HomeRoot $script:fakeHome } | Should -Throw
        }
    }

    It 'checks in the page that the token and the secret are plain hex before it can save' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText.Contains("var secret = String(document.body.getAttribute('data-secret'));") | Should -BeTrue
        $scriptText.Contains('var valid = /^[0-9a-f]{8}$/.test(token) && /^[0-9a-f]{32}$/.test(secret);') | Should -BeTrue
        $scriptText.Contains('if (!valid) { save.disabled = true; }') | Should -BeTrue
        $scriptText.Contains('if (ids.length === 0 || !valid) { return; }') | Should -BeTrue
    }

    It 'lets a name set its own text direction without reordering the cells around it' {
        $script:html | Should -Match '\.name,\.folder\{[^}]*unicode-bidi:isolate'
        ([regex]::Matches($script:html, '<td class="name" dir="auto">')).Count | Should -Be 5
        ([regex]::Matches($script:html, '<td class="folder" dir="auto">')).Count | Should -Be 5
    }

    It 'ticks a row only through its checkbox and its label, never through a click on the row' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText.Contains("body.addEventListener('change', refresh);") | Should -BeTrue
        ([regex]::Matches($scriptText, "addEventListener\('click'")).Count | Should -Be 2
        $scriptText | Should -Match "order\.addEventListener\('click'"
        $scriptText | Should -Match "save\.addEventListener\('click'"
        $scriptText | Should -Not -Match '\.checked\s*=[^=]'
        $scriptText | Should -Not -Match '(?i)onclick'
        $script:html | Should -Not -Match '\.name label\{[^}]*display:block'
    }

    It 'says how many ticked items the filter is hiding, in both languages' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText.Contains('if (row.hidden) { unseen += 1; }') | Should -BeTrue
        $scriptText.Contains("if (unseen > 0) { line += words.unseen.replace('{n}', String(unseen)); }") | Should -BeTrue
        ([regex]::Matches($scriptText, "\bunseen: ' \(\{n\} ")).Count | Should -Be 2
        $scriptText | Should -Match 'hidden by the filter'
        $scriptText | Should -Match 'tersembunyi oleh filter'
        $scriptText | Should -Match "(?s)filter\.addEventListener\('change', function \(\) \{.*?refresh\(\);\s*\}\);"
    }

    It 'refuses an item with an unknown group' {
        $odd = Get-FakeItem -Id 1 -Name 'zqfile.bin' -Group '"><script>alert(1)</script>'

        { Get-ReviewReportHtml -Token 'a1b2c3d4' -Secret $script:fakeSecret -Items @($odd) -HomeRoot $script:fakeHome } | Should -Throw
    }

    It 'explains in plain words that nothing is deleted here and warns about synced folders' {
        $script:html | Should -Match 'Nothing is deleted from this page'
        $script:html | Should -Match 'moved to the Recycle Bin only after you press Save selection'
        $script:html | Should -Match 'OneDrive, iCloud or Dropbox'
        $script:html | Should -Match 'removed from the cloud and from your other devices'
    }

    It 'saves exactly the agreed selection document and starts with the button disabled' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText.Contains("'{`"token`":`"' + token + '`",`"secret`":`"' + secret + '`",`"ids`":[' + ids.join(',') + ']}'") | Should -BeTrue
        $scriptText.Contains("link.download = 'disk-cleanup-selection.json';") | Should -BeTrue
        $scriptText | Should -Match 'new Blob\('
        $script:html.Contains('<button type="button" id="save" disabled data-t="save">Save selection</button>') | Should -BeTrue
        $scriptText | Should -Match 'save\.disabled = chosen\.length === 0;'
    }

    It 'switches to Indonesian from navigator.language and has every text in both languages' {
        $scriptText = Get-ScriptBlockText -Html $script:html

        $scriptText | Should -Match "navigator\.language \|\| 'en'\)\.toLowerCase\(\)\.indexOf\('id'\) === 0"
        $scriptText | Should -Match 'Simpan pilihan'
        $scriptText | Should -Match 'Tidak ada yang dihapus dari halaman ini'
        $keys = @([regex]::Matches($script:html, 'data-t="([A-Za-z0-9]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $keys.Count | Should -BeGreaterThan 15
        foreach ($key in $keys) {
            ([regex]::Matches($scriptText, ('\b' + $key + ': ''')).Count) | Should -Be 2
        }
    }

    It 'is accessible: labelled controls, a live summary, a table caption and both colour schemes' {
        $script:html | Should -Match '<html lang="en">'
        $script:html | Should -Match '<label for="filter"'
        $script:html | Should -Match '<caption '
        $script:html | Should -Match '<th scope="col"'
        $script:html | Should -Match 'id="summary" aria-live="polite"'
        $script:html | Should -Match 'prefers-color-scheme:dark'
        $script:html | Should -Match ':focus-visible'
        ([regex]::Matches($script:html, '<label for="pick[0-9]+">')).Count | Should -Be 5
    }

    It 'renders an empty list without rows' {
        $empty = Get-ReviewReportHtml -Token 'a1b2c3d4' -Secret $script:fakeSecret -Items @() -HomeRoot $script:fakeHome

        $empty | Should -Not -Match '<tr data-id='
        $empty | Should -Match 'id="empty" hidden'
        $empty.Contains($script:csp) | Should -BeTrue
    }

    It 'formats <Bytes> bytes as <Expected>' -ForEach @(
        @{ Bytes = 0; Expected = '0 B' }
        @{ Bytes = 1023; Expected = '1023 B' }
        @{ Bytes = 1024; Expected = '1.0 KB' }
        @{ Bytes = 1536; Expected = '1.5 KB' }
        @{ Bytes = 10485760; Expected = '10.0 MB' }
        @{ Bytes = 5368709120; Expected = '5.0 GB' }
        @{ Bytes = 1099511627776; Expected = '1.0 TB' }
        @{ Bytes = 2251799813685248; Expected = '2048.0 TB' }
    ) {
        Format-ByteSize -Bytes $Bytes | Should -BeExactly $Expected
    }

    It 'shows the profile folder itself as ~' {
        Get-ReviewDisplayFolder -Path ($script:fakeHome + '\zqfile.bin') -HomeRoot $script:fakeHome | Should -BeExactly '~'
        Get-ReviewDisplayFolder -Path ($script:fakeHome + '\Videos\zqfile.bin') -HomeRoot ($script:fakeHome + '\') | Should -BeExactly '~\Videos'
        Get-ReviewDisplayFolder -Path 'D:\zqelsewhere\zqfile.bin' -HomeRoot $script:fakeHome | Should -BeExactly '~'
    }
}

Describe 'review report on disk' {
    BeforeEach {
        Set-StrictMode -Version Latest
        $script:sandbox = Initialize-Sandbox -Root $TestDrive
        $script:files = Add-SandboxReviewFixture -Sandbox $script:sandbox
        Mock Get-AccountProfilePath { $null }
        Mock Get-DiskInfo { [pscustomobject]@{ TotalBytes = [long]2000000; FreeBytes = [long]1000000 } }
        Mock Open-ReviewReport { $true }
        Mock Get-AllocatedFileSize { $null }
    }

    AfterEach {
        Restore-SandboxEnvironment
    }

    It 'writes real file names that carry shell and HTML characters as escaped text' {
        $odd = 'zq&amp;''$(calc)`[1]{2};%TEMP% =x.bin'
        Add-SandboxBigFile -Path (Join-Path -Path $script:sandbox.Home -ChildPath ('Videos\zq&co ''s\' + $odd)) -SizeMb 13

        $run = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '10')

        $run.Data.total_item_count | Should -Be 6
        $report = [System.IO.File]::ReadAllText($script:sandbox.Report)
        $report.Contains('zq&amp;amp;&#39;$(calc)`[1]{2};%TEMP% =x.bin</label>') | Should -BeTrue
        $report.Contains('<td class="folder" dir="auto">~\Videos\zq&amp;co &#39;s</td>') | Should -BeTrue
        $report | Should -Not -Match 'zq&co'
        $report.Contains($script:csp) | Should -BeTrue
        Assert-PrivateOutput -Json $run.Json -Sandbox $script:sandbox
    }

    It 'shows folders relative to the profile and never the profile path' {
        $run = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '10')

        $report = [System.IO.File]::ReadAllText($script:sandbox.Report)
        $report.Contains('<td class="folder" dir="auto">~\Videos</td>') | Should -BeTrue
        $report.Contains('<td class="folder" dir="auto">~\Downloads</td>') | Should -BeTrue
        $report | Should -Not -Match 'zqfixtureuser'
        $report | Should -Not -Match ([regex]::Escape((Split-Path -Path $script:sandbox.Base -Leaf)))
        $secret = Get-SandboxSecret -Manifest $script:sandbox.Manifest
        $report.Contains('<body data-token="' + $run.Data.token + '" data-secret="' + $secret + '">') | Should -BeTrue
        $run.Json | Should -Not -Match $secret
        ([regex]::Matches($report, '<tr data-id=')).Count | Should -Be 5
    }

    It 'writes the report as UTF-8 without a byte order mark and keeps non-ASCII names readable' {
        $name = 'zqcaf' + [char]233 + '-' + [char]26085 + [char]26412 + '.mov'
        Add-SandboxBigFile -Path (Join-Path -Path $script:sandbox.Home -ChildPath ('Videos\' + $name)) -SizeMb 14

        $null = Invoke-CleanupJson -Arguments @('review', '--min-size-mb', '10')

        $bytes = [System.IO.File]::ReadAllBytes($script:sandbox.Report)
        $bytes[0] | Should -Be 60
        $report = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false).GetString($bytes)
        $report.Contains($name + '</label>') | Should -BeTrue
        $report | Should -Match '<meta charset="utf-8">'
        (Get-SandboxManifestPathList -Manifest $script:sandbox.Manifest) -join '|' | Should -Match ([regex]::Escape($name))
    }
}
