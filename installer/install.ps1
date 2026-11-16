# Balatro Multiplayer - one-click installer for players.
# Installs Lovely (mod loader), Steamodded (mod framework) and the Balatro Multiplayer mod.
# Already-installed Lovely/Steamodded are left alone.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# Versions the mod was tested with.
$LovelyUrl = 'https://github.com/ethangreen-dev/lovely-injector/releases/download/v0.10.0/lovely-x86_64-pc-windows-msvc.zip'
$SmodsUrl  = 'https://github.com/Steamodded/smods/archive/refs/tags/26.1002.0.zip'

function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Done($msg) { Write-Host "    $msg" -ForegroundColor Green }

function Find-BalatroDir {
  $candidates = @()
  try {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    if ($steam) {
      $candidates += (Join-Path $steam 'steamapps\common\Balatro')
      $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
      if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
          $candidates += (Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Balatro')
        }
      }
    }
  } catch {}
  $candidates += 'C:\Program Files (x86)\Steam\steamapps\common\Balatro'
  foreach ($c in $candidates) { if (Test-Path (Join-Path $c 'Balatro.exe')) { return $c } }
  return $null
}

function Download-Extract($url, $name) {
  $tmp = Join-Path $env:TEMP ("bmp-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $zip = Join-Path $tmp "$name.zip"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
  $out = Join-Path $tmp 'x'
  Expand-Archive -Path $zip -DestinationPath $out -Force
  return $out
}

try {
  Write-Host 'Balatro Multiplayer installer' -ForegroundColor Yellow

  if (Get-Process -Name 'Balatro' -ErrorAction SilentlyContinue) {
    Write-Host 'Balatro is running. Please close it, then press Enter.' -ForegroundColor Yellow
    Read-Host | Out-Null
  }

  Step 'Finding Balatro'
  $game = Find-BalatroDir
  while (-not $game) {
    $p = Read-Host 'Could not find Balatro. Paste the Balatro game folder (Steam > Balatro > Manage > Browse local files)'
    if (Test-Path (Join-Path $p 'Balatro.exe')) { $game = $p } else { Write-Host 'Balatro.exe not found there.' -ForegroundColor Red }
  }
  Done $game

  Step 'Lovely (mod loader)'
  if ((Test-Path (Join-Path $game 'winmm.dll')) -or (Test-Path (Join-Path $game 'version.dll'))) {
    Done 'already installed'
  } else {
    $x = Download-Extract $LovelyUrl 'lovely'
    $dll = Get-ChildItem $x -Recurse -Filter 'winmm.dll' | Select-Object -First 1
    if (-not $dll) { throw 'winmm.dll not found in the Lovely download' }
    try {
      Copy-Item $dll.FullName (Join-Path $game 'winmm.dll')
    } catch {
      throw "Could not write to $game. Right-click Install.bat and choose 'Run as administrator'."
    }
    Done 'installed'
  }

  $mods = Join-Path $env:APPDATA 'Balatro\Mods'
  New-Item -ItemType Directory -Force $mods | Out-Null

  Step 'Steamodded (mod framework)'
  $existing = Get-ChildItem $mods -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'src\core.lua') } | Select-Object -First 1
  if ($existing) {
    Done "already installed ($($existing.Name))"
  } else {
    $x = Download-Extract $SmodsUrl 'smods'
    $root = Get-ChildItem $x -Directory | Select-Object -First 1
    Move-Item $root.FullName (Join-Path $mods 'smods')
    Done 'installed'
  }

  Step 'Balatro Multiplayer mod'
  $src = Join-Path $PSScriptRoot 'BalatroMultiplayer'
  if (-not (Test-Path (Join-Path $src 'main.lua'))) { throw 'BalatroMultiplayer folder is missing next to this installer. Unzip the whole package first.' }
  $dst = Join-Path $mods 'BalatroMultiplayer'
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  Copy-Item -Recurse $src $dst
  Done 'installed'

  Write-Host ''
  Write-Host 'All done! Launch Balatro from Steam and click MULTIPLAYER on the main menu.' -ForegroundColor Green
  Write-Host 'Your friend can now invite you from their lobby (Invite Steam Friends).'
} catch {
  Write-Host ''
  Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press Enter to close'
