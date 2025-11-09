param(
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Always operate from the script directory (repo root)
# Normalize root to forward slashes and operate from there
$Root = ($PSScriptRoot -replace '\\','/')
Set-Location -Path $Root

# Paths (use forward slashes)
$modRoot = "$Root/mining-telemetry"
$infoPath = "$modRoot/info.json"

if (-not (Test-Path $infoPath)) {
    throw "info.json not found at $infoPath"
}

# Read name/version from info.json
$info = Get-Content $infoPath -Raw | ConvertFrom-Json
if (-not $info) { throw 'Unable to parse info.json' }
if ($info.factorio_version -ne '2.0') { Write-Warning "factorio_version is $($info.factorio_version); expected 2.0" }

$name    = $info.name
$version = $info.version
$folderName = "$name`_$version"
$zipName    = "$folderName.zip"

# Validate minimal required files exist before packaging
$required = @('info.json', 'control.lua', 'data.lua', 'settings.lua')
$missing  = @()
foreach ($f in $required) {
    if (-not (Test-Path "$modRoot/$f")) { $missing += $f }
}
if ($missing.Count -gt 0) {
    throw "Missing required files in mining-telemetry: $($missing -join ', ')"
}

# Staging directory to ensure correct top-level folder inside the zip
$stagingRoot = "$Root/.build"
$stagingMod  = "$stagingRoot/$folderName"

# Optional clean
if ($Clean) {
    if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $zipName)     { Remove-Item $zipName -Force -ErrorAction SilentlyContinue }
}

# Prepare staging
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
if (Test-Path $stagingMod) { Remove-Item $stagingMod -Recurse -Force }
New-Item -ItemType Directory -Path $stagingMod | Out-Null

# Copy mod contents into name_version staging folder
# This copies all playable mod files; repository extras (like .junie) are outside modRoot and won't be included.
Copy-Item -Path "$modRoot/*" -Destination $stagingMod -Recurse -Force

# Remove any pre-existing zip
if (Test-Path $zipName) { Remove-Item $zipName -Force }

# Create the zip with the correct top-level folder name, ensuring forward slash separators
# Use System.IO.Compression.ZipArchive to control entry names (Compress-Archive uses '\\' which breaks on Linux/macOS)

# Ensure compression assemblies are available
try { Add-Type -AssemblyName System.IO.Compression } catch {}
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch {}

$zipPath = "$Root/$zipName"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        # Add files from the staged folder, but prefix with the top-level folder name
        Get-ChildItem -Path $stagingMod -Recurse -File | ForEach-Object {
            $full = $_.FullName
            $rel  = $full.Substring($stagingMod.Length + 1)
            $rel  = $rel -replace '\\','/'
            $entryName = "$folderName/$rel"

            $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $inStream = [System.IO.File]::OpenRead($full)
                try { $inStream.CopyTo($entryStream) } finally { $inStream.Dispose() }
            } finally {
                $entryStream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
} finally {
    $fs.Dispose()
}

# Basic report and cleanup staging
Write-Host "Created $zipName" -ForegroundColor Green

# Remove staging (keep .build folder for speed if desired)
Remove-Item $stagingMod -Recurse -Force -ErrorAction SilentlyContinue

# Final smoke message
"OK: Packaged $name $version -> $zipName"