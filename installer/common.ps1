# Shared by install.ps1 and uninstall.ps1.

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

# Ask for the game folder when Steam's library list doesn't lead to it.
function Get-BalatroDir {
  $game = Find-BalatroDir
  while (-not $game) {
    $p = Read-Host 'Could not find Balatro. Paste the Balatro game folder (Steam > Balatro > Manage > Browse local files)'
    if (Test-Path (Join-Path $p 'Balatro.exe')) { $game = $p } else { Write-Host 'Balatro.exe not found there.' -ForegroundColor Red }
  }
  return $game
}

function Wait-BalatroClosed {
  while (Get-Process -Name 'Balatro' -ErrorAction SilentlyContinue) {
    Write-Host 'Balatro is running. Please close it, then press Enter.' -ForegroundColor Yellow
    Read-Host | Out-Null
  }
}

$ModsDir = Join-Path $env:APPDATA 'Balatro\Mods'
