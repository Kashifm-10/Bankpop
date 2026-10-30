@echo off
rem Builds dist\django-mail-api.zip for drag-and-drop deploys (e.g. Wasmer Edge).
rem Windows twin of build-zip.sh. Zip entries use forward slashes so Linux hosts unpack it correctly.
setlocal
set "BZ_SELF=%~f0"
set "BZ_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:BZ_SELF); $m='#'+'BUILD-ZIP-SCRIPT#'; iex $s.Substring($s.IndexOf($m))"
exit /b %ERRORLEVEL%

#BUILD-ZIP-SCRIPT#
$ErrorActionPreference = 'Stop'
Set-Location $env:BZ_DIR
uv export --no-hashes --no-dev --format requirements-txt -o requirements.txt -q
if ($LASTEXITCODE) { throw 'uv export failed' }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$root = (Get-Location).Path
$out = Join-Path $root 'dist\django-mail-api.zip'
New-Item -ItemType Directory -Force (Join-Path $root 'dist') | Out-Null
if (Test-Path $out) { Remove-Item $out }

$skip = '^(\.venv|\.git|dist|flutter_client|postman)(/|$)|(^|/)__pycache__(/|$)|^\.env$|\.pyc$'
$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
    Get-ChildItem -Path $root -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($rel -notmatch $skip) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel)
        }
    }
} finally {
    $zip.Dispose()
}
Write-Host 'built dist\django-mail-api.zip'
