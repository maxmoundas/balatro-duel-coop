# Builds dist\BalatroMultiplayer-Setup.zip for friends: unzip, double-click Install.bat (Windows)
# or run files/install-mac.sh (macOS). tools/build-friend-package.sh builds the same zip on a Mac.
# Players host games themselves in-game and friends join through Steam, so no server is needed.
# Optional -Server "host:port" bakes in a dedicated server instead.
param([string]$Server = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'BalatroMultiplayer-Setup'
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
Copy-Item -Recurse (Join-Path $root 'mod\BalatroMultiplayer') (Join-Path $files 'BalatroMultiplayer')

if ($Server) {
  # Optional: point everyone at a dedicated server instead of in-game hosting.
  if ($Server -notmatch '^(.+):(\d+)$') { throw 'Server must look like host:port' }
  $hostName, $port = $Matches[1], $Matches[2]
  $cfgPath = Join-Path $stage 'files\BalatroMultiplayer\config.lua'
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
