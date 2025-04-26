# not working, because torch would runtime fail without this dll
$envDir="$env:CONDA_PREFIX"

$fileToHide="libiomp5md.dll"

Get-ChildItem -Path "$envDir\Lib" -Filter $fileToHide -Recurse | ForEach-Object {
    $path = $_.FullName
    $newPath = "$path.hidden"
    Move-Item -Path $path -Destination $newPath
    Write-Host "Moved $path to $newPath"
}