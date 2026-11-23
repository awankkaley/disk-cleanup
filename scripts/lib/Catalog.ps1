# Known desktop apps whose cache folders belong to the app-caches category.
# To add an app, append one row. Base is Home (%USERPROFILE%), Local (%LOCALAPPDATA%)
# or Roaming (%APPDATA%); Path is the app data folder below it; Processes are the
# process names (without .exe) that mean the app is open. Only the folder names in
# APP_CACHE_DIR_NAMES are ever cleaned inside that app folder.
$script:KNOWN_APP_CACHES = @(
    @{ Name = 'Slack'; Base = 'Roaming'; Path = 'Slack'; Processes = @('slack') },
    @{ Name = 'Discord'; Base = 'Roaming'; Path = 'discord'; Processes = @('Discord') },
    @{ Name = 'Microsoft Teams'; Base = 'Roaming'; Path = 'Microsoft\Teams'; Processes = @('Teams') },
    @{ Name = 'Spotify'; Base = 'Local'; Path = 'Spotify\Browser'; Processes = @('Spotify') },
    @{ Name = 'Visual Studio Code'; Base = 'Roaming'; Path = 'Code'; Processes = @('Code') }
)
$script:APP_CACHE_DIR_NAMES = @('Cache', 'Code Cache', 'GPUCache', 'CachedData')

$script:CHROMIUM_CACHE_NAMES = @('Cache', 'Code Cache', 'GPUCache')
$script:FIREFOX_CACHE_NAMES = @('cache2', 'startupCache')
$script:CHROMIUM_PROFILE_PATTERN = '^(Default|Profile [0-9]+|Guest Profile)$'
$script:ANY_PROFILE_PATTERN = '.'
$script:ARC_USER_DATA = 'Packages\TheBrowserCompany.Arc_*\LocalCache\Local\Arc\User Data'

# Roots are folders that hold profile folders. RootIsProfile marks browsers that
# also keep caches directly in the root folder (Opera).
$script:BROWSERS = @(
    @{ Id = 'browser-chrome'; Processes = @('chrome'); CacheNames = $script:CHROMIUM_CACHE_NAMES
        ProfilePattern = $script:CHROMIUM_PROFILE_PATTERN; RootIsProfile = $false
        Roots = @(@{ Base = 'Local'; Path = 'Google\Chrome\User Data' }) },
    @{ Id = 'browser-edge'; Processes = @('msedge'); CacheNames = $script:CHROMIUM_CACHE_NAMES
        ProfilePattern = $script:CHROMIUM_PROFILE_PATTERN; RootIsProfile = $false
        Roots = @(@{ Base = 'Local'; Path = 'Microsoft\Edge\User Data' }) },
    @{ Id = 'browser-firefox'; Processes = @('firefox'); CacheNames = $script:FIREFOX_CACHE_NAMES
        ProfilePattern = $script:ANY_PROFILE_PATTERN; RootIsProfile = $false
        Roots = @(@{ Base = 'Local'; Path = 'Mozilla\Firefox\Profiles' }) },
    @{ Id = 'browser-brave'; Processes = @('brave'); CacheNames = $script:CHROMIUM_CACHE_NAMES
        ProfilePattern = $script:CHROMIUM_PROFILE_PATTERN; RootIsProfile = $false
        Roots = @(@{ Base = 'Local'; Path = 'BraveSoftware\Brave-Browser\User Data' }) },
    @{ Id = 'browser-opera'; Processes = @('opera'); CacheNames = $script:CHROMIUM_CACHE_NAMES
        ProfilePattern = $script:CHROMIUM_PROFILE_PATTERN; RootIsProfile = $true
        Roots = @(
            @{ Base = 'Local'; Path = 'Opera Software\Opera Stable' },
            @{ Base = 'Roaming'; Path = 'Opera Software\Opera Stable' }
        ) },
    @{ Id = 'browser-arc'; Processes = @('Arc'); CacheNames = $script:CHROMIUM_CACHE_NAMES
        ProfilePattern = $script:CHROMIUM_PROFILE_PATTERN; RootIsProfile = $false
        Roots = @(@{ Base = 'Local'; Path = $script:ARC_USER_DATA }) }
)

$script:SIMPLE_DIRECTORY_CATEGORIES = @{
    'temp-files'      = @{ Base = 'Local'; Paths = @('Temp'); UseAgeCutoff = $true; FilePatterns = @()
        Processes = @(); CommandLinePattern = '' }
    'crash-dumps'     = @{ Base = 'Local'; Paths = @('CrashDumps'); UseAgeCutoff = $true; FilePatterns = @()
        Processes = @(); CommandLinePattern = '' }
    'thumbnail-cache' = @{ Base = 'Local'; Paths = @('Microsoft\Windows\Explorer'); UseAgeCutoff = $false
        FilePatterns = @('thumbcache_*.db', 'iconcache_*.db'); Processes = @(); CommandLinePattern = '' }
    'gradle-cache'    = @{ Base = 'Home'; Paths = @('.gradle\caches'); UseAgeCutoff = $false; FilePatterns = @()
        Processes = @('java', 'javaw'); CommandLinePattern = '*GradleDaemon*' }
    'cargo-cache'     = @{ Base = 'Home'; Paths = @('.cargo\registry\cache', '.cargo\registry\src')
        UseAgeCutoff = $false; FilePatterns = @(); Processes = @(); CommandLinePattern = '' }
}

# Only the per-package folders Windows itself treats as disposable. LocalCache is
# left alone on purpose: many Store apps keep real user data in it.
$script:STORE_PACKAGE_ROOT = 'Packages'
$script:STORE_APP_CACHE_SUBPATHS = @('TempState', 'AC\INetCache')

# A tool's own clean command runs only when the tool reports a cache directory at or
# below DefaultPath. FallbackDelete allows a guarded delete of the default directory
# when the tool cannot report one; SizeUnknown marks caches whose freeable size
# cannot be known before cleaning (the pnpm store is hardlinked into projects).
$script:TOOL_CATEGORIES = @{
    'npm-cache'  = @{ Tool = 'npm'; DirArguments = @('config', 'get', 'cache'); SubPath = '_cacache'
        DefaultBase = 'Local'; DefaultPath = 'npm-cache'; CleanArguments = @('cache', 'clean', '--force')
        FallbackDelete = $true; SizeUnknown = $false }
    'yarn-cache' = @{ Tool = 'yarn'; DirArguments = @('cache', 'dir'); SubPath = ''
        DefaultBase = 'Local'; DefaultPath = 'Yarn\Cache'; CleanArguments = @('cache', 'clean')
        FallbackDelete = $true; SizeUnknown = $false }
    'pnpm-store' = @{ Tool = 'pnpm'; DirArguments = @('store', 'path'); SubPath = ''
        DefaultBase = 'Local'; DefaultPath = 'pnpm\store'; CleanArguments = @('store', 'prune')
        FallbackDelete = $false; SizeUnknown = $true }
    'pip-cache'  = @{ Tool = 'pip'; DirArguments = @('cache', 'dir'); SubPath = ''
        DefaultBase = 'Local'; DefaultPath = 'pip\Cache'; CleanArguments = @('cache', 'purge')
        FallbackDelete = $true; SizeUnknown = $false }
    'go-cache'   = @{ Tool = 'go'; DirArguments = @('env', 'GOCACHE'); SubPath = ''
        DefaultBase = 'Local'; DefaultPath = 'go-build'; CleanArguments = @('clean', '-cache')
        FallbackDelete = $true; SizeUnknown = $false }
}

$script:DOCKER_TOOL = 'docker'
$script:DOCKER_INFO_ARGUMENTS = @('info')
$script:DOCKER_LIST_ARGUMENTS = @('images', '--filter', 'dangling=true', '--quiet')
$script:DOCKER_PRUNE_ARGUMENTS = @('image', 'prune', '--force')
$script:DOCKER_RECLAIMED_PATTERN = 'Total reclaimed space:\s*([0-9]+(?:\.[0-9]+)?)\s*([kKMGT]?B)'
$script:DOCKER_UNIT_FACTORS = @{ 'B' = 1; 'KB' = 1000; 'MB' = 1000000; 'GB' = 1000000000; 'TB' = 1000000000000 }

$script:TRASH_ID = 'trash'
$script:NODE_MODULES_ID = 'node-modules-stale'
$script:TRASH_FLAG = '--empty-trash'

$script:IMPACT_APP_CACHE = 'Apps may start slightly slower once while their caches rebuild.'
$script:IMPACT_TEMP = 'None expected; only temporary files older than the age threshold are removed.'
$script:IMPACT_THUMBNAIL = 'File Explorer regenerates thumbnails and icons the next time folders are opened.'
$script:IMPACT_CRASH_DUMP = 'Old crash dumps are no longer available for troubleshooting.'
$script:IMPACT_STORE_APP = 'Store apps may load slightly slower once while their caches rebuild.'
$script:IMPACT_TRASH = 'Everything in the Recycle Bin is permanently deleted and cannot be restored.'
$script:IMPACT_BROWSER = 'Pages may load slightly slower once while the cache rebuilds.'
$script:IMPACT_PACKAGE = 'Packages are downloaded again the next time they are installed.'
$script:IMPACT_PNPM = 'Only packages that no project references are removed; the amount freed is known after cleaning.'
$script:IMPACT_BUILD = 'The next build is slower while the cache is rebuilt.'
$script:IMPACT_DOCKER = 'Only untagged dangling image layers are removed; tagged images and volumes are kept.'
$script:IMPACT_NODE_MODULES = 'Idle projects need a package install before they can run again.'

# Fixed output order of the scan. Kind selects the handler; ids and labels are static.
$script:CATEGORIES = @(
    @{ Id = 'app-caches'; Label = 'App caches'; Group = 'system'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_APP_CACHE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'temp-files'; Label = 'Temporary files'; Group = 'system'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_TEMP; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'thumbnail-cache'; Label = 'Thumbnail cache'; Group = 'system'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_THUMBNAIL; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'crash-dumps'; Label = 'Crash dumps'; Group = 'system'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_CRASH_DUMP; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'store-app-caches'; Label = 'Store app caches'; Group = 'system'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_STORE_APP; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'trash'; Label = 'Recycle Bin'; Group = 'system'; Risk = 'irreversible'; Kind = 'trash'
        Impact = $script:IMPACT_TRASH; RequiresFlag = $script:TRASH_FLAG; DeepOnly = $false },
    @{ Id = 'browser-chrome'; Label = 'Chrome cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'browser-edge'; Label = 'Edge cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'browser-firefox'; Label = 'Firefox cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'browser-brave'; Label = 'Brave cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'browser-opera'; Label = 'Opera cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'browser-arc'; Label = 'Arc cache'; Group = 'browser'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_BROWSER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'npm-cache'; Label = 'npm cache'; Group = 'developer'; Risk = 'safe'; Kind = 'tool'
        Impact = $script:IMPACT_PACKAGE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'yarn-cache'; Label = 'Yarn cache'; Group = 'developer'; Risk = 'safe'; Kind = 'tool'
        Impact = $script:IMPACT_PACKAGE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'pnpm-store'; Label = 'pnpm store'; Group = 'developer'; Risk = 'safe'; Kind = 'tool'
        Impact = $script:IMPACT_PNPM; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'pip-cache'; Label = 'pip cache'; Group = 'developer'; Risk = 'safe'; Kind = 'tool'
        Impact = $script:IMPACT_PACKAGE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'gradle-cache'; Label = 'Gradle cache'; Group = 'developer'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_PACKAGE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'cargo-cache'; Label = 'Cargo registry cache'; Group = 'developer'; Risk = 'safe'; Kind = 'directory'
        Impact = $script:IMPACT_PACKAGE; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'go-cache'; Label = 'Go build cache'; Group = 'developer'; Risk = 'safe'; Kind = 'tool'
        Impact = $script:IMPACT_BUILD; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'docker-dangling'; Label = 'Docker dangling images'; Group = 'developer'; Risk = 'safe'; Kind = 'docker'
        Impact = $script:IMPACT_DOCKER; RequiresFlag = $null; DeepOnly = $false },
    @{ Id = 'node-modules-stale'; Label = 'Stale node_modules'; Group = 'projects'; Risk = 'rebuild_needed'
        Kind = 'node-modules'; Impact = $script:IMPACT_NODE_MODULES; RequiresFlag = $null; DeepOnly = $true }
)

$script:SAFE_RISK = 'safe'

# Canonical result error codes, shared with the macOS script. A result gets the code
# of its status unless the handler names a more specific one (CUSTOM_LOCATION,
# TOOL_FAILED, GUARD_REFUSED).
$script:STATUS_ERROR_CODES = @{
    'cleaned'               = $null
    'skipped_running'       = 'APP_RUNNING'
    'skipped_no_permission' = 'PERMISSION_DENIED'
    'partial'               = 'SOME_ITEMS_REMAIN'
    'not_found'             = 'NOT_FOUND'
    'unavailable'           = 'TOOL_UNAVAILABLE'
    'failed'                = 'INTERNAL'
}
