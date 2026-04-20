#Requires -Version 5.1

param(
    [ValidateSet("prod", "dev")]
    [string]$BuildType = "prod"
)

# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$appExecutableRoot = if ($BuildType -eq "prod") { "DTImageSearch" } else { "DTImageSearch-$BuildType" }
$appExecutablePath = "$appExecutableRoot\$appExecutableRoot.exe"
$msixOutputName = if ($BuildType -eq "prod") { "DTImageSearch.msix" } else { "DTImageSearch-$BuildType.msix" }

# Get script directory and change to repo root (equivalent to bash path resolution)
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$repoRoot = Join-Path $scriptDir "../.."
Set-Location $repoRoot

Write-Host "Changed to repository root: $(Get-Location)"

Remove-Item -Force -Recurse -ErrorAction Ignore .\DTImageSearchApp
Remove-Item -Force -Recurse -ErrorAction Ignore .\build
Remove-Item -Force -Recurse -ErrorAction Ignore .\dist

& "$scriptDir\build.ps1"
. "$scriptDir\utils.ps1"

# Run PyInstaller
Write-Host "Running PyInstaller..."
$previousBuildType = $env:DTIS_BUILD_TYPE
$env:DTIS_BUILD_TYPE = $BuildType
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
} finally {
    if ($null -eq $previousBuildType) {
        Remove-Item Env:\DTIS_BUILD_TYPE -ErrorAction Ignore
    } else {
        $env:DTIS_BUILD_TYPE = $previousBuildType
    }
}

# Create and clean DTImageSearchApp directory
Write-Host "Setting up DTImageSearchApp directory..."
$appDir = Join-Path $repoRoot "DTImageSearchApp"
if (Test-Path "$appDir") {
    Remove-Item -Path "$appDir" -Recurse -Force
}

# Move dist contents to DTImageSearchApp
if (Test-Path "dist") {
    Move-Item -Path "dist" -Destination "$appDir"
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

# Apply build-type specific app identity/display values in AppxManifest.
try {
    [xml]$manifestXml = Get-Content -Path $manifestDst
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($manifestXml.NameTable)
    $namespaceManager.AddNamespace("appx", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
    $namespaceManager.AddNamespace("uap", "http://schemas.microsoft.com/appx/manifest/uap/windows10")
    $namespaceManager.AddNamespace("desktop2", "http://schemas.microsoft.com/appx/manifest/desktop/windows10/2")

    $identityNode = $manifestXml.SelectSingleNode("/appx:Package/appx:Identity", $namespaceManager)
    $displayNameNode = $manifestXml.SelectSingleNode("/appx:Package/appx:Properties/appx:DisplayName", $namespaceManager)
    $applicationNode = $manifestXml.SelectSingleNode("/appx:Package/appx:Applications/appx:Application", $namespaceManager)
    $visualElementsNode = $manifestXml.SelectSingleNode("/appx:Package/appx:Applications/appx:Application/uap:VisualElements", $namespaceManager)
    $firewallRulesNode = $manifestXml.SelectSingleNode("/appx:Package/appx:Extensions/desktop2:Extension/desktop2:FirewallRules", $namespaceManager)

    if ($null -eq $applicationNode -or $null -eq $firewallRulesNode) {
        throw "AppxManifest.xml is missing required application executable nodes."
    }

    $applicationNode.SetAttribute("Executable", $appExecutablePath)
    $firewallRulesNode.SetAttribute("Executable", $appExecutablePath)

    if ($BuildType -ne "prod") {
        $displaySuffix = "-$BuildType"
        if ($null -ne $displayNameNode -and -not $displayNameNode.InnerText.EndsWith($displaySuffix)) {
            $displayNameNode.InnerText = "$($displayNameNode.InnerText)$displaySuffix"
        }
        if ($null -ne $visualElementsNode) {
            $currentDisplayName = $visualElementsNode.GetAttribute("DisplayName")
            if ($currentDisplayName -and -not $currentDisplayName.EndsWith($displaySuffix)) {
                $visualElementsNode.SetAttribute("DisplayName", "$currentDisplayName$displaySuffix")
            }
        }
        if ($null -ne $applicationNode) {
            $currentApplicationId = $applicationNode.GetAttribute("Id")
            if ($currentApplicationId -and -not $currentApplicationId.EndsWith($displaySuffix)) {
                $applicationNode.SetAttribute("Id", "$currentApplicationId$displaySuffix")
            }
        }
        if ($null -ne $identityNode) {
            $currentIdentityName = $identityNode.GetAttribute("Name")
            $identitySuffix = ".$BuildType"
            if ($currentIdentityName -and -not $currentIdentityName.EndsWith($identitySuffix)) {
                $identityNode.SetAttribute("Name", "$currentIdentityName$identitySuffix")
            }
        }
    }

    $manifestXml.Save($manifestDst)
    Write-Host "Updated AppxManifest.xml for build type '$BuildType'"
} catch {
    Write-Error "Failed to apply build type manifest values: $($_.Exception.Message)"
    exit 1
}

# Execute bump_app_version.ps1 to update version
$bumpScript = Join-Path $scriptDir "bump_app_version.ps1"
Write-Host "Bumping app version..."
try {
    & $bumpScript -manifest $manifestDst
    Write-Host "App version bumped successfully"
} catch {
    Write-Error "Failed to bump app version: $($_.Exception.Message)"
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
        "/d", "$appDir",
        "/p", $msixOutputName,
        "/o"
    ) -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Error "Failed to create MSIX package."
        exit 1
    }
    
    Write-Host "Successfully created MSIX package: $msixOutputName"
} catch {
    Write-Error "Failed to create MSIX package: $($_.Exception.Message)"
    exit 1
}

Write-Host "MSIX packaging completed successfully!"
