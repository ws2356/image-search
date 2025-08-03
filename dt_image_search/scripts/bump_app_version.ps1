param(
    [string]$manifest
)

# Set strict mode and error action
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$revision = git rev-list --count '@'

# Get the Identity/Version value of dt_image_search\resources\AppxManifest.xml 
if (Test-Path $manifest) {
    [xml]$manifestObj = Get-Content $manifest
    $identityVersion = $manifestObj.Package.Identity.Version
}

if ($identityVersion -match '(\d+)\.(\d+)\.(\d+)') {
    $major = $matches[1]
    $minor = $matches[2]
    $build = $matches[3]
    $newVersion = "$major.$minor.$build.$revision"
} else {
    Write-Error "Failed to parse version from AppxManifest.xml"
    exit 1
}

# Update the version in AppxManifest.xml
$manifestObj.Package.Identity.Version = $newVersion
$manifestObj.Save($manifest)