# Builds dist\BalatroMultiplayer-Setup.zip for friends: unzip, double-click Install.bat.
# Players host games themselves in-game and friends join through Steam, so no server is needed.
# Optional -Server "host:port" bakes in a dedicated server instead.
param([string]$Server = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'BalatroMultiplayer-Setup'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null

# Install.bat, Uninstall.bat and the scripts they run.
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

@"
BALATRO MULTIPLAYER - SETUP
===========================
1. Make sure you own Balatro on Steam and have launched it at least once.
2. Close Balatro.
3. Double-click Install.bat (if Windows warns you, click "More info" > "Run anyway").
4. Launch Balatro from Steam and click MULTIPLAYER on the main menu.

To uninstall: close Balatro and double-click Uninstall.bat. It removes this mod, then asks
whether to also remove Lovely and Steamodded (keep them if you use other mods).
Your Balatro saves are never touched.
"@ | Set-Content -Path (Join-Path $stage 'README.txt') -Encoding ascii

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
