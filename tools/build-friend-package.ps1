# Builds dist\BalatroMultiplayer-Setup.zip for friends: unzip, double-click Install.bat (Windows)
# or run install-mac.sh (macOS). tools/build-friend-package.sh builds the same zip on a Mac.
# Players host games themselves in-game and friends join through Steam, so no server is needed.
# Optional -Server "host:port" bakes in a dedicated server instead.
param([string]$Server = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'BalatroMultiplayer-Setup'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

# Install.bat/Uninstall.bat (Windows), install-mac.sh/uninstall-mac.sh (macOS), the scripts they
# run and README.txt.
Copy-Item (Join-Path $root 'installer\*') $stage
Copy-Item -Recurse (Join-Path $root 'mod\BalatroMultiplayer') (Join-Path $stage 'BalatroMultiplayer')

if ($Server) {
  # Optional: point everyone at a dedicated server instead of in-game hosting.
  if ($Server -notmatch '^(.+):(\d+)$') { throw 'Server must look like host:port' }
  $hostName, $port = $Matches[1], $Matches[2]
  $cfgPath = Join-Path $stage 'BalatroMultiplayer\config.lua'
  $cfg = (Get-Content $cfgPath -Raw) -replace "server_host = ''", "server_host = '$hostName'" -replace "server_port = '8788'", "server_port = '$port'"
  Set-Content -Path $cfgPath -Value $cfg -Encoding ascii -NoNewline
}

$zip = Join-Path $dist 'BalatroMultiplayer-Setup.zip'
if (Test-Path $zip) { Remove-Item -Force $zip }
# Build the zip by hand: Compress-Archive on PowerShell 5.1 writes '\' path separators,
# which some unzip tools mishandle.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  foreach ($f in Get-ChildItem $stage -Recurse -File) {
    $rel = $f.FullName.Substring($stage.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $rel) | Out-Null
  }
} finally { $archive.Dispose() }
Write-Host "Built $zip" -ForegroundColor Green
if ($Server) { Write-Host "Dedicated server: $Server" } else { Write-Host 'In-game hosting (friends join through Steam).' }
