
param(
    [Parameter(Mandatory)]
    [ValidateSet("dev", "main")]
    [string]$Target
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$manifest = Get-Content (Join-Path $root "manifest.json") -Raw |
    ConvertFrom-Json

$id = $manifest.id

if ($id -notmatch '^[a-z0-9-]+$') {
    throw "Invalid plugin ID: $id"
}

# Target directories point to .obsidian, not the vault root.
switch ($Target) {
    "dev" {
        $obsidianDir = [IO.Path]::GetFullPath(
            (Join-Path $root "..\_obsidian-dev-vault\.obsidian")
        )
        $buildCommand = "build:dev"
    }
    "main" {
        $obsidianDir = "C:\Users\Taras\Documents\obsidian-vault\.obsidian"
        $buildCommand = "build"
    }
}

if (-not (Test-Path $obsidianDir -PathType Container)) {
    throw "Obsidian configuration directory not found: $obsidianDir"
}

$destination = Join-Path $obsidianDir "plugins\$id"

# Protect against copying through a junction or symlink.
if (Test-Path $destination) {
    $item = Get-Item $destination -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Destination is a junction or symlink: $destination"
    }
}

Push-Location $root
try {
    Write-Host "Building $id ($Target)..."

    & npm.cmd run $buildCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }

    $files = @("main.js", "manifest.json", "styles.css")

    foreach ($file in $files) {
        if (-not (Test-Path $file -PathType Leaf)) {
            throw "Missing build artifact: $file"
        }
    }

    New-Item -ItemType Directory -Force $destination |
        Out-Null

    foreach ($file in $files) {
        Copy-Item $file (Join-Path $destination $file) -Force
    }

    New-Item -ItemType File -Force `
    -Path (Join-Path $destination ".hotreload") |
    Out-Null
    
    Write-Host "Deployed $id to $Target vault." -ForegroundColor Green
}
finally {
    Pop-Location
}
