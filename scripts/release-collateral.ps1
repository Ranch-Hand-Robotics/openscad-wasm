param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [string]$Repo = "",

    [string]$BuildDir = "build",

    [string]$OutDir = ".release",

    [switch]$Upload,

    [switch]$CreateRelease
)

$ErrorActionPreference = "Stop"

# In PowerShell 7+, avoid non-zero native exit codes being converted to terminating errors
# so we can handle gh exit codes explicitly.
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Require-Path([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "Required path not found: $Path"
    }
}

function Resolve-RepoSlug([string]$ExplicitRepo) {
    if ($ExplicitRepo -and $ExplicitRepo.Trim().Length -gt 0) {
        return $ExplicitRepo.Trim()
    }

    $remoteUrl = ""
    try {
        $remoteUrl = (& git remote get-url origin 2>$null).Trim()
    } catch {
        $remoteUrl = ""
    }

    if (-not $remoteUrl) {
        return "openscad/openscad-wasm"
    }

    if ($remoteUrl -match 'github\.com[:/](?<slug>[^/]+/[^/.]+)(\.git)?$') {
        return $matches['slug']
    }

    return "openscad/openscad-wasm"
}

function Get-Sha256([string]$Path) {
    $getFileHash = Get-Command Get-FileHash -ErrorAction SilentlyContinue
    if ($getFileHash) {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $certutil = Get-Command certutil -ErrorAction SilentlyContinue
    if (-not $certutil) {
        throw "Neither Get-FileHash nor certutil is available to compute SHA256"
    }

    $raw = (& certutil -hashfile $Path SHA256) -join "`n"
    if ($raw -match '(?im)\b([a-f0-9]{64})\b') {
        return $matches[1].ToLowerInvariant()
    }

    throw "Unable to parse SHA256 from certutil output"
}

$Repo = Resolve-RepoSlug $Repo

$requiredFiles = @(
    "openscad.js",
    "openscad.wasm.js",
    "openscad.wasm",
    "openscad.fonts.js",
    "openscad.mcad.js",
    "files.d.ts",
    "openscad.d.ts",
    "openscad.fonts.d.ts",
    "openscad.mcad.d.ts"
)

Require-Path $BuildDir

foreach ($file in $requiredFiles) {
    Require-Path (Join-Path $BuildDir $file)
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$stagingDirName = "openscad-wasm-collateral-$Tag"
$stagingDir = Join-Path $OutDir $stagingDirName
$zipPath = Join-Path $OutDir "$stagingDirName.zip"
$checksumPath = Join-Path $OutDir "$stagingDirName.sha256"

if (Test-Path $stagingDir) {
    Remove-Item -Recurse -Force $stagingDir
}
New-Item -ItemType Directory -Path $stagingDir | Out-Null

foreach ($file in $requiredFiles) {
    Copy-Item (Join-Path $BuildDir $file) (Join-Path $stagingDir $file) -Force
}

$optionalFiles = @("openscad.wasm.map")
foreach ($file in $optionalFiles) {
    $source = Join-Path $BuildDir $file
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $stagingDir $file) -Force
    }
}

$notesPath = Join-Path $stagingDir "README.txt"
@"
OpenSCAD WASM collateral bundle for GitHub Release tag: $Tag

Contents:
- openscad.js: runtime wrapper module
- openscad.wasm.js + openscad.wasm: core WASM runtime
- openscad.fonts.js: embedded font assets
- openscad.mcad.js: embedded MCAD library assets
- *.d.ts: TypeScript declarations

This bundle is intended for direct consumption without npm.
"@ | Set-Content -Encoding utf8 $notesPath

if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}
Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

$hash = Get-Sha256 $zipPath
"$hash  $(Split-Path -Leaf $zipPath)" | Set-Content -Encoding ascii $checksumPath

Write-Host "[ok] Collateral package created: $zipPath"
Write-Host "[ok] SHA256 file created: $checksumPath"

if ($Upload -or $CreateRelease) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw "GitHub CLI (gh) not found. Install gh or run without -Upload/-CreateRelease."
    }
}

if ($CreateRelease) {
    & gh release view $Tag --repo $Repo 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[*] Creating release $Tag in $Repo"
        & gh release create $Tag --repo $Repo --title $Tag --notes "OpenSCAD WASM collateral bundle for $Tag"
        if ($LASTEXITCODE -ne 0) {
            throw "gh release create failed for $Repo tag $Tag"
        }
    } else {
        Write-Host "[*] Release $Tag already exists in $Repo"
    }
}

if ($Upload) {
    Write-Host "[*] Uploading assets to $Repo release $Tag"
    & gh release upload $Tag $zipPath $checksumPath --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) {
        throw "gh release upload failed for $Repo tag $Tag"
    }
    Write-Host "[ok] Uploaded collateral assets to release $Tag"
}
