param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$files = Get-ChildItem -LiteralPath $repository -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Sort-Object Name |
    ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -File -Recurse |
            Where-Object { $_.Name -eq 'SKILL.md' -or $_.FullName.EndsWith('agents\openai.yaml') }
    }

$lines = @("path`tsize_bytes`tsha256")
foreach ($file in $files) {
    $relative = $file.FullName.Substring($repository.Length + 1).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $lines += "$relative`t$($file.Length)`t$hash"
}

$manifest = Join-Path $repository 'SKILL_MANIFEST.tsv'
[System.IO.File]::WriteAllLines($manifest, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Output "MANIFEST_FILES=$($files.Count)"
Write-Output "MANIFEST_PATH=$manifest"
