# disk-cleanup for Windows (Windows PowerShell 5.1).
# Usage: cleanup.ps1 scan [--deep] [--min-age-days N] [--projects-dir PATH] [--target-gb N]
#        cleanup.ps1 clean --token ID --categories id1,id2 [--empty-trash] [--min-idle-days N] [--log]
#        cleanup.ps1 review [--min-size-mb N] [--downloads-age-days N]
#        cleanup.ps1 review-apply --token ID
# Prints exactly one JSON document on stdout. The known-app cache table that
# contributors extend lives at the top of lib\Catalog.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libraryDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'lib'
. (Join-Path -Path $libraryDirectory -ChildPath 'Catalog.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Core.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'FileSystem.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Platform.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Plans.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'NodeModules.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Review.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'ReviewReport.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'ReviewApply.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Options.ps1')
. (Join-Path -Path $libraryDirectory -ChildPath 'Commands.ps1')

# Dot-sourcing (tests) only loads the functions; direct invocation runs the command.
if ($MyInvocation.InvocationName -ne '.') {
    # 'a,b' typed inside a PowerShell session arrives as an array; rejoin it.
    $flatArguments = [string[]]@(foreach ($argument in $args) {
            if ($argument -is [array]) { $argument -join ',' } else { [string]$argument }
        })
    $outcome = Invoke-Cleanup -Arguments $flatArguments
    Write-Output $outcome.Json
    exit $outcome.ExitCode
}
