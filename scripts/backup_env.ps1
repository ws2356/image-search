#!/usr/bin/env pwsh

conda list --explicit > environment_backup.txt
conda env export | select-string -Pattern '^\s*prefix:' -NotMatch > environment.yml

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$otherBackupFile = Join-Path $repoRoot "environment_other.txt"

# clear otherBackupFile
if (Test-Path $otherBackupFile) {
    Remove-Item $otherBackupFile -Force
}

$otherSourceRepos = @("clip-retrieval", "autofaiss")
foreach ($repo in $otherSourceRepos) {
    $repoPath = Join-Path (Split-Path -Path "$repoRoot" -Parent) $repo
    if (Test-Path $repoPath) {
        echo "======$repo======" >> $otherBackupFile
        pushd $repoPath
        echo "======repo url======" >> $otherBackupFile
        git remote -v >> $otherBackupFile
        echo "======revision======" >> $otherBackupFile
        git log -1 >> $otherBackupFile
        echo "" >> $otherBackupFile
        popd
    } else {
        Write-Host "$repo not found in the repository."
    }
}