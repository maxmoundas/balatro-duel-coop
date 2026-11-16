@echo off
rem Starts the Balatro Multiplayer relay server on port 8788 (keep this window open while playing).
rem Optional: only needed for a dedicated server. Normally players host from inside the game.
cd /d "%~dp0server"
if not exist node_modules call npm install --omit=dev
node src\server.js
pause
