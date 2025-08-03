#Requires -Version 5.1

param()

# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get script directory and change to repo root (equivalent to bash path resolution)
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
Set-Location (Join-Path $scriptDir "../..")

Write-Host "Changed to repository root: $(Get-Location)"

Remove-Item -Force -Recurse -ErrorAction Ignore .\DTImageSearchApp
Remove-Item -Force -Recurse -ErrorAction Ignore .\build
Remove-Item -Force -Recurse -ErrorAction Ignore .\dist

. "$scriptDir\utils.ps1"

# Run PyInstaller
Write-Host "Running PyInstaller..."
try {
    $pyinstallerProcess = Start-Process -FilePath "pyinstaller" -ArgumentList "dt_image_search/DTImageSearch.spec" -Wait -PassThru -NoNewWindow
    if ($pyinstallerProcess.ExitCode -ne 0) {
        Write-Error "PyInstaller failed with exit code: $($pyinstallerProcess.ExitCode)"
        exit 1
    }
    Write-Host "PyInstaller completed successfully"
} catch {
    Write-Error "Failed to run PyInstaller: $($_.Exception.Message)"
    exit 1
}

# Create and clean DTImageSearchApp directory
Write-Host "Setting up DTImageSearchApp directory..."
$appDir = "DTImageSearchApp"
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
if (Test-Path "$appDir\*") {
    Remove-Item -Path "$appDir\*" -Recurse -Force
}

# Move dist contents to DTImageSearchApp
if (Test-Path "dist") {
    $distItems = Get-ChildItem -Path "dist"
    foreach ($item in $distItems) {
        Move-Item -Path $item.FullName -Destination $appDir -Force
    }
    Write-Host "Moved contents from dist to DTImageSearchApp"
} else {
    Write-Error "dist directory not found"
    exit 1
}

# Copy manifest and icon
$manifestSrc = "dt_image_search\resources\AppxManifest.xml"
$manifestDst = Join-Path $appDir "AppxManifest.xml"
if (Test-Path $manifestSrc) {
    Copy-Item -Path $manifestSrc -Destination $manifestDst -Force
    Write-Host "Copied AppxManifest.xml"
} else {
    Write-Error "AppxManifest.xml not found at: $manifestSrc"
    exit 1
}

$iconSrc = "dt_image_search\resources\appicon.iconset\icon_512x512@2x.png"
$iconDst = Join-Path $appDir "icon.png"
if (Test-Path $iconSrc) {
    Copy-Item -Path $iconSrc -Destination $iconDst -Force
    Write-Host "Copied icon.png"
} else {
    Write-Error "Icon file not found at: $iconSrc"
    exit 1
}

# Find makeappx.exe
$makeappx = Search-MakeAppx
if (-not $makeappx -or -not (Test-Path $makeappx)) {
    Write-Error "makeappx not found. Please install Windows SDK."
    exit 1
}

Write-Host "Found makeappx at: $makeappx"

# Create MSIX package
Write-Host "Creating MSIX package..."
try {
    $process = Start-Process -FilePath $makeappx -ArgumentList @(
        "pack",
        "/d", "DTImageSearchApp",
        "/p", "DTImageSearch.msix",
        "/o"
    ) -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Error "Failed to create MSIX package."
        exit 1
    }
    
    Write-Host "Successfully created MSIX package: DTImageSearch.msix"
} catch {
    Write-Error "Failed to create MSIX package: $($_.Exception.Message)"
    exit 1
}

Write-Host "MSIX packaging completed successfully!"