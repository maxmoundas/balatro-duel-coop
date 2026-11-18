# Balatro Duel & Co-op - uninstaller for players.
# Always removes the Balatro Duel & Co-op mod and its settings. Then asks whether to also
# remove Lovely and Steamodded (the mod loaders), which other mods may still need.
# Never touches Balatro itself or your save files.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Ask-YesNo($question) {
  while ($true) {
    $a = (Read-Host "$question [y/N]").Trim().ToLower()
    if ($a -eq '' -or $a -eq 'n' -or $a -eq 'no') { return $false }
    if ($a -eq 'y' -or $a -eq 'yes') { return $true }
  }
}

# A loader DLL in the game folder counts as Lovely only if it says so, so we never
# delete some other program's winmm.dll / version.dll.
function Get-LovelyDlls($game) {
  $out = @()
  foreach ($name in 'winmm.dll', 'version.dll') {
    $path = Join-Path $game $name
    if (Test-Path $path) {
      $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($path))
      if ($text -match 'lovely') { $out += $path }
    }
  }
  return $out
}

try {
  Write-Host 'Balatro Duel & Co-op uninstaller' -ForegroundColor Yellow
  Wait-BalatroClosed

  Step 'Balatro Duel & Co-op mod'
  $mod = Join-Path $ModsDir 'BalatroMultiplayer'
  if (Test-Path $mod) {
    Remove-Item -Recurse -Force $mod
    Done 'removed'
  } else {
    Done 'not installed'
  }
  # Settings (name, server) saved by Steamodded.
  $cfg = Join-Path $env:APPDATA 'Balatro\config\BalatroMultiplayerDuelCoop.jkr'
  if (Test-Path $cfg) { Remove-Item -Force $cfg; Done 'settings removed' }

  # Lovely + Steamodded: optional, other mods depend on them.
  $smods = @()
  if (Test-Path $ModsDir) {
    $smods = @(Get-ChildItem $ModsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'src\core.lua') })
  }
  $game = Find-BalatroDir
  $lovely = if ($game) { @(Get-LovelyDlls $game) } else { @() }

  if ($smods.Count -gt 0 -or $lovely.Count -gt 0) {
    $others = @()
    if (Test-Path $ModsDir) {
      $skip = @('lovely') + ($smods | ForEach-Object { $_.Name })
      $others = @(Get-ChildItem $ModsDir -Directory | Where-Object { $skip -notcontains $_.Name } | ForEach-Object { $_.Name })
    }
    Write-Host ''
    Write-Host 'Lovely and Steamodded (the mod loaders) are still installed.' -ForegroundColor Cyan
    if ($others.Count -gt 0) {
      Write-Host "You have other mods that need them: $($others -join ', ')" -ForegroundColor Yellow
      Write-Host 'Keep them unless you want to remove ALL mods.' -ForegroundColor Yellow
    } else {
      Write-Host 'No other mods use them. Removing them makes Balatro completely unmodded again.'
    }

    if (Ask-YesNo 'Also remove Lovely and Steamodded?') {
      Step 'Steamodded'
      foreach ($d in $smods) { Remove-Item -Recurse -Force $d.FullName; Done "removed $($d.Name)" }
      $smodsCfg = Join-Path $env:APPDATA 'Balatro\config\Steamodded.jkr'
      if (Test-Path $smodsCfg) { Remove-Item -Force $smodsCfg }
      Step 'Lovely'
      foreach ($dll in $lovely) {
        try {
          Remove-Item -Force $dll
          Done "removed $(Split-Path $dll -Leaf)"
        } catch {
          throw "Could not delete $dll. Right-click Uninstall.bat and choose 'Run as administrator'."
        }
      }
      $lovelyData = Join-Path $ModsDir 'lovely' # Lovely's logs and patch dumps
      if (Test-Path $lovelyData) { Remove-Item -Recurse -Force $lovelyData; Done 'removed Lovely logs' }
      if ((Test-Path $ModsDir) -and -not (Get-ChildItem $ModsDir -Force)) { Remove-Item -Force $ModsDir }
    } else {
      Done 'kept Lovely and Steamodded'
    }
  }

  Write-Host ''
  Write-Host 'Done. Your Balatro saves were not touched.' -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press Enter to close'
