# Builds dist\BalatroDuelCoop-Setup.zip for friends: unzip, double-click Install.bat (Windows)
# or run files/install-mac.sh (macOS). tools/build-friend-package.sh builds the same zip on a Mac.
# Players host games themselves in-game and friends join through Steam, so no server is needed.
# Also builds the release zips for mod managers and listings (skipped with -Server):
#   dist\BalatroDuelCoop.zip              the mod folder only (Mod Index / Balatro Mod Manager, Nexus)
#   dist\BalatroDuelCoop-Thunderstore.zip manifest.json, icon.png, README.md + the mod's files at the root
# Optional -Server "host:port" bakes in a dedicated server instead.
param([string]$Server = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'BalatroDuelCoop-Setup'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

# Only what Windows players double-click (Install.bat, Uninstall.bat) and README.txt sit at the
# top; the scripts they run, the Mac scripts and the mod itself go in files\.
$files = Join-Path $stage 'files'
New-Item -ItemType Directory -Force $files | Out-Null
$top = @('Install.bat', 'Uninstall.bat', 'README.txt')
foreach ($f in Get-ChildItem (Join-Path $root 'installer') -File) {
  Copy-Item $f.FullName $(if ($top -contains $f.Name) { $stage } else { $files })
}
Copy-Item -Recurse (Join-Path $root 'mod\BalatroDuelCoop') (Join-Path $files 'BalatroDuelCoop')

if ($Server) {
  # Optional: point everyone at a dedicated server instead of in-game hosting.
  if ($Server -notmatch '^(.+):(\d+)$') { throw 'Server must look like host:port' }
  $hostName, $port = $Matches[1], $Matches[2]
  $cfgPath = Join-Path $stage 'files\BalatroDuelCoop\config.lua'
  $cfg = (Get-Content $cfgPath -Raw) -replace "server_host = ''", "server_host = '$hostName'" -replace "server_port = '8788'", "server_port = '$port'"
  Set-Content -Path $cfgPath -Value $cfg -Encoding ascii -NoNewline
}

# Build zips by hand: Compress-Archive on PowerShell 5.1 writes '\' path separators,
# which some unzip tools mishandle. Entries are named relative to $base.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function New-Zip($zip, $dir, $base) {
  if (Test-Path $zip) { Remove-Item -Force $zip }
  $archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
  try {
    foreach ($f in Get-ChildItem $dir -Recurse -File) {
      $rel = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $rel) | Out-Null
    }
  } finally { $archive.Dispose() }
  Write-Host "Built $zip" -ForegroundColor Green
}

New-Zip (Join-Path $dist 'BalatroDuelCoop-Setup.zip') $stage $stage
if ($Server) { Write-Host "Dedicated server: $Server"; return }
Write-Host 'In-game hosting (friends join through Steam).'

# The version lives in the mod's json; the Thunderstore manifest must match it.
$modDir = Join-Path $root 'mod\BalatroDuelCoop'
$version = (Get-Content (Join-Path $modDir 'BalatroDuelCoop.json') -Raw | ConvertFrom-Json).version
$tsSrc = Join-Path $root 'publish\thunderstore'
$tsVersion = (Get-Content (Join-Path $tsSrc 'manifest.json') -Raw | ConvertFrom-Json).version_number
if ($version -ne $tsVersion) { throw "Version mismatch: mod json says $version, publish\thunderstore\manifest.json says $tsVersion" }

New-Zip (Join-Path $dist 'BalatroDuelCoop.zip') $modDir (Join-Path $root 'mod')

$ts = Join-Path $dist 'BalatroDuelCoop-Thunderstore'
if (Test-Path $ts) { Remove-Item -Recurse -Force $ts }
Copy-Item -Recurse $modDir $ts
foreach ($f in 'manifest.json', 'icon.png', 'README.md') { Copy-Item (Join-Path $tsSrc $f) $ts }
New-Zip (Join-Path $dist 'BalatroDuelCoop-Thunderstore.zip') $ts $ts
Write-Host "Version $version"

