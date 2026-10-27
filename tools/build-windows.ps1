# Builds dist\QrawllerTerminal-win64\QrawllerTerminal.exe on Windows.
# Easiest way to run it: double-click tools\build-windows.bat
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$LoveVersion = "11.5"
$Name = "QrawllerTerminal"
$Root = Split-Path -Parent $PSScriptRoot
$Build = Join-Path $Root "build"
$Dist = Join-Path $Root "dist"
$Cache = Join-Path $Build "cache"
New-Item -ItemType Directory -Force $Build, $Dist, $Cache | Out-Null

# 1. pack the game (.love is just a zip)
$Stage = Join-Path $Build "stage"
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory $Stage | Out-Null
foreach ($item in "main.lua", "conf.lua", "config.lua", "src", "commands", "widgets", "assets") {
    Copy-Item -Recurse (Join-Path $Root $item) $Stage
}
$LoveFile = Join-Path $Build "qrawller.love"
if (Test-Path $LoveFile) { Remove-Item $LoveFile }
[System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $LoveFile)
Write-Host "packed  $LoveFile"

# 2. get the LÖVE runtime
$ZipName = "love-$LoveVersion-win64"
$RuntimeZip = Join-Path $Cache "$ZipName.zip"
if (-not (Test-Path $RuntimeZip)) {
    Write-Host "downloading LOVE $LoveVersion ..."
    Invoke-WebRequest "https://github.com/love2d/love/releases/download/$LoveVersion/$ZipName.zip" -OutFile $RuntimeZip
}
$Runtime = Join-Path $Cache $ZipName
if (Test-Path $Runtime) { Remove-Item -Recurse -Force $Runtime }
Expand-Archive $RuntimeZip -DestinationPath $Cache -Force

# 3. fuse: love.exe + game = our exe
$Out = Join-Path $Dist "$Name-win64"
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory $Out | Out-Null
$Exe = Join-Path $Out "$Name.exe"
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $Runtime "love.exe")) + [System.IO.File]::ReadAllBytes($LoveFile)
[System.IO.File]::WriteAllBytes($Exe, $bytes)
Copy-Item (Join-Path $Runtime "*.dll") $Out
Copy-Item (Join-Path $Runtime "license.txt") (Join-Path $Out "love-license.txt")
Copy-Item (Join-Path $Root "assets\fonts\LICENSE.txt") (Join-Path $Out "font-license.txt")

Write-Host ""
Write-Host "built   $Exe" -ForegroundColor Red
Write-Host "keep the .dll files next to the .exe"
