# Copies the mod into Balatro's Mods folder (requires Lovely + Steamodded already installed).
$src = Join-Path $PSScriptRoot 'mod\BalatroDuelCoop'
$mods = Join-Path $env:APPDATA 'Balatro\Mods'
$dst = Join-Path $mods 'BalatroDuelCoop'

if (-not (Test-Path $mods)) { New-Item -ItemType Directory -Force $mods | Out-Null }
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
Copy-Item -Recurse $src $dst
Write-Host "Installed to $dst"

$hasSmods = Get-ChildItem $mods -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'src\core.lua') }
if (-not $hasSmods) { Write-Warning 'Steamodded not found in the Mods folder - see README for setup.' }
$gameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Balatro'
if (-not ((Test-Path (Join-Path $gameDir 'winmm.dll')) -or (Test-Path (Join-Path $gameDir 'version.dll')))) { Write-Warning "Lovely (winmm.dll) not found in $gameDir - see README for setup." }
