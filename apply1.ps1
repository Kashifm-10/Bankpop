#Requires -Version 5.1
<#
.SYNOPSIS
    Remove the red scan-frame border from QRPayScanner.

.DESCRIPTION
    The red box in lib/pages/transactions/pay.dart is a leftover from the
    qr_code_scanner package, which drew a scan window. mobile_scanner detects
    a barcode anywhere in the preview, so the frame was decorative and has
    been removed. The card-mode hint at the bottom of the screen is kept.

.USAGE
    cd <project root>
    powershell -ExecutionPolicy Bypass -File .\apply_scanner_cleanup.ps1
#>

param([string]$ProjectRoot = ".")

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
if (-not (Test-Path (Join-Path $ProjectRoot 'pubspec.yaml'))) {
    throw "Not a Flutter project: $ProjectRoot (pubspec.yaml missing)"
}

$payPath = Join-Path $ProjectRoot 'lib/pages/transactions/pay.dart'
if (-not (Test-Path $payPath)) { throw "Required file missing: $payPath" }

# ---- Backup -------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $ProjectRoot ".backup-scanner-$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$rel  = $payPath.Substring($ProjectRoot.Length).TrimStart('\', '/')
$dest = Join-Path $backupDir $rel
New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
Copy-Item $payPath $dest
Write-Host "Backed up to: $backupDir" -ForegroundColor Cyan

# ---- Helpers ------------------------------------------------------------
function Normalize-Lf   { param([string]$s) ($s -replace "`r`n", "`n") }
function Normalize-Crlf { param([string]$s) ((($s -replace "`r`n", "`n")) -replace "`n", "`r`n") }

function Edit-File {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Search,
        [Parameter(Mandatory)] [string]$Replace,
        [Parameter(Mandatory)] [string]$Name
    )
    $content  = [System.IO.File]::ReadAllText($Path)
    $usesCrlf = $content.Contains("`r`n")
    $s = if ($usesCrlf) { Normalize-Crlf $Search }  else { Normalize-Lf $Search }
    $r = if ($usesCrlf) { Normalize-Crlf $Replace } else { Normalize-Lf $Replace }
    $count = ([regex]::Matches($content, [regex]::Escape($s))).Count
    if ($count -eq 0) { throw "[$Name] anchor not found in $(Split-Path $Path -Leaf). File unchanged." }
    if ($count -gt 1) { throw "[$Name] anchor not unique in $(Split-Path $Path -Leaf) ($count matches). File unchanged." }
    $newContent = $content.Replace($s, $r)
    [System.IO.File]::WriteAllText($Path, $newContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  [OK] {0,-40} {1}" -f $Name, (Split-Path $Path -Leaf)) -ForegroundColor Green
}

# =========================================================================
# pay.dart -- drop the red frame, keep the card-mode hint
# =========================================================================
Write-Host "`nEditing pay.dart" -ForegroundColor Yellow

Edit-File -Path $payPath -Name 'pay: drop red scan frame' -Search @'
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // The scan frame the old scanner drew. MobileScanner has no overlay
          // API, so it is a plain red border over the same 250.w window.
          Center(
            child: IgnorePointer(
              child: Container(
                width: 250.w,
                height: 250.w,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 10),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          if (widget.isCardMode)
'@ -Replace @'
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          if (widget.isCardMode)
'@

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Done. Backup: $backupDir" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  flutter analyze"
Write-Host "  Open Pay / Buy Card and confirm the camera fills the screen"
Write-Host "  with no red box; the 'Scan the bank's property card QR to"
Write-Host "  buy it' hint still appears when isCardMode is true."
Write-Host ""
Write-Host "To roll back: Copy-Item '$backupDir\lib\*' 'lib\' -Recurse -Force" -ForegroundColor DarkGray