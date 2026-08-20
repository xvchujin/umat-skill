param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$errors = [System.Collections.Generic.List[string]]::new()

$expectedSkills = @(
    'abaqus-tensor-voigt-adapter',
    'constitutive-domain-stabilization-audit',
    'cpa-implicit-return-mapping',
    'ddsdde-finite-difference-audit',
    'explicit-adaptive-substepping',
    'explicit-alpha-yield-intersection',
    'explicit-yield-drift-correction',
    'hill48-yield-calibration-applicability-audit',
    'j2-isotropic-hardening-radial-return',
    'softening-objectivity-audit',
    'tsai-wu-damage-state-machine',
    'tsai-wu-parameter-audit',
    'umat-failure-cutback-protocol',
    'umat-hierarchical-validation',
    'umat-props-statev-contract',
    'umat-semantic-debugging',
    'umat-transactional-state-update',
    'umat-update-mechanism-router'
) | Sort-Object
$allowedPublicFiles = @(
    '.gitattributes',
    '.gitignore',
    'CHANGELOG.md',
    'PUBLICATION_POLICY.md',
    'README.md',
    'SKILL_MANIFEST.tsv',
    'tools/update-skill-manifest.ps1',
    'tools/verify-public-release.ps1'
)
foreach ($skill in $expectedSkills) {
    $allowedPublicFiles += "$skill/SKILL.md"
    $allowedPublicFiles += "$skill/agents/openai.yaml"
}

$skillDirectories = Get-ChildItem -LiteralPath $repository -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Sort-Object Name
$actualSkills = $skillDirectories.Name

$missing = $expectedSkills | Where-Object { $_ -notin $actualSkills }
$unexpected = $actualSkills | Where-Object { $_ -notin $expectedSkills }
if ($missing) { $errors.Add("Missing skills: $($missing -join ', ')") }
if ($unexpected) { $errors.Add("Unexpected skills: $($unexpected -join ', ')") }

$forbiddenExtensions = @(
    '.pdf', '.caj', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx',
    '.png', '.jpg', '.jpeg', '.gif', '.tif', '.tiff', '.bmp', '.svg',
    '.mp3', '.wav', '.mp4', '.avi', '.mov', '.mkv',
    '.zip', '.7z', '.rar', '.tar', '.gz',
    '.for', '.f', '.f90', '.obj', '.dll', '.exe',
    '.inp', '.odb', '.cae', '.jnl', '.msg', '.dat', '.sta', '.log'
)
$forbiddenPathSegments = '(?i)(^|[\\/])(\.build|transcripts?|corpus|candidates?|source|extensions?|preprocessed|rejected|stage\d[^\\/]*)([\\/]|$)'

$allFiles = Get-ChildItem -LiteralPath $repository -File -Recurse |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

$buildDirectory = Join-Path $repository '.build'
if (Test-Path -LiteralPath $buildDirectory) {
    $errors.Add("Build directory is not permitted in a public release: .build")
}

foreach ($file in $allFiles) {
    $relative = $file.FullName.Substring($repository.Length + 1)
    $normalizedRelative = $relative.Replace('\', '/')
    if ($normalizedRelative -notin $allowedPublicFiles) {
        $errors.Add("Unexpected public release file: $relative")
    }
    if ($file.Extension.ToLowerInvariant() -in $forbiddenExtensions) {
        $errors.Add("Forbidden extension: $relative")
    }
    if ($relative -match $forbiddenPathSegments) {
        $errors.Add("Forbidden path segment: $relative")
    }
    if ($file.Length -gt 262144) {
        $errors.Add("File exceeds 256 KiB: $relative")
    }
    if ($file.LinkType) {
        $errors.Add("Links are not allowed: $relative")
    }
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes -contains 0) {
        $errors.Add("NUL byte or binary content: $relative")
    }
}

foreach ($directory in $skillDirectories) {
    $skillPath = Join-Path $directory.FullName 'SKILL.md'
    $text = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
    $frontmatterMatch = [regex]::Match($text, '(?ms)\A---\r?\n(.*?)\r?\n---')
    $nameMatch = [regex]::Match($text, '(?m)^name:\s*([^\r\n]+)$')
    $descriptionMatch = [regex]::Match($text, '(?m)^description:\s*(?:\|\s*)?$')
    if (-not $frontmatterMatch.Success) {
        $errors.Add("Missing YAML frontmatter: $($directory.Name)/SKILL.md")
    }
    if (-not $nameMatch.Success -or $nameMatch.Groups[1].Value.Trim() -ne $directory.Name) {
        $errors.Add("Frontmatter name mismatch: $($directory.Name)/SKILL.md")
    }
    if (-not $descriptionMatch.Success) {
        $errors.Add("Missing block description: $($directory.Name)/SKILL.md")
    }
    if ($frontmatterMatch.Success) {
        $topLevelKeys = [regex]::Matches($frontmatterMatch.Groups[1].Value, '(?m)^([a-zA-Z0-9_-]+):') |
            ForEach-Object { $_.Groups[1].Value }
        $extraKeys = $topLevelKeys | Where-Object { $_ -notin @('name', 'description') }
        if ($extraKeys) {
            $errors.Add("Unexpected frontmatter keys in $($directory.Name)/SKILL.md: $($extraKeys -join ', ')")
        }
    }
    if (($text -split "`r?`n").Count -gt 500) {
        $errors.Add("SKILL.md exceeds 500 lines: $($directory.Name)/SKILL.md")
    }

    $allowedFiles = @('SKILL.md', 'agents\openai.yaml')
    $directoryFiles = Get-ChildItem -LiteralPath $directory.FullName -File -Recurse
    foreach ($file in $directoryFiles) {
        $relativeWithinSkill = $file.FullName.Substring($directory.FullName.Length + 1)
        if ($relativeWithinSkill -notin $allowedFiles) {
            $errors.Add("Unexpected public skill file: $($directory.Name)/$relativeWithinSkill")
        }
    }

    $contentChecks = @(
        @{ Pattern = '(?m)^\s*>\s'; Label = 'Markdown quotation block' },
        @{ Pattern = '\.\.[\\/]'; Label = 'parent-directory link' },
        @{ Pattern = '\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b'; Label = 'media timecode' },
        @{ Pattern = '(?i)jishulink|技术邻|transcripts?|逐字稿|核对版视频'; Label = 'private source marker' }
    )
    foreach ($check in $contentChecks) {
        if ($text -match $check.Pattern) {
            $errors.Add("$($check.Label): $($directory.Name)/SKILL.md")
        }
    }

    $relatedSection = [regex]::Match($text, '(?ms)^## 相关 skills\s*$.*?(?=^## |\z)')
    if (-not $relatedSection.Success) {
        $errors.Add("Missing routing section: $($directory.Name)/SKILL.md")
    }

    $agentPath = Join-Path $directory.FullName 'agents\openai.yaml'
    if (-not (Test-Path -LiteralPath $agentPath)) {
        $errors.Add("Missing agents/openai.yaml: $($directory.Name)")
    } else {
        $agentText = Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
        $displayMatch = [regex]::Match($agentText, '(?m)^\s{2}display_name:\s*"([^"]+)"\s*$')
        $shortMatch = [regex]::Match($agentText, '(?m)^\s{2}short_description:\s*"([^"]+)"\s*$')
        $promptMatch = [regex]::Match($agentText, '(?m)^\s{2}default_prompt:\s*"([^"]+)"\s*$')
        if (-not $displayMatch.Success) { $errors.Add("Invalid display_name: $($directory.Name)/agents/openai.yaml") }
        if (-not $shortMatch.Success -or $shortMatch.Groups[1].Value.Length -lt 25 -or $shortMatch.Groups[1].Value.Length -gt 64) {
            $errors.Add("short_description must be 25-64 chars: $($directory.Name)/agents/openai.yaml")
        }
        if (-not $promptMatch.Success -or $promptMatch.Groups[1].Value -notlike "*`$$($directory.Name)*") {
            $errors.Add("default_prompt must mention `$$($directory.Name): $($directory.Name)/agents/openai.yaml")
        }
    }
}

$manifestPath = Join-Path $repository 'SKILL_MANIFEST.tsv'
$manifestFiles = @(
    foreach ($directory in $skillDirectories) {
        Get-ChildItem -LiteralPath $directory.FullName -File -Recurse |
            Where-Object { $_.Name -eq 'SKILL.md' -or $_.FullName.EndsWith('agents\openai.yaml') }
    }
) | Sort-Object FullName
$expectedManifestLines = @("path`tsize_bytes`tsha256")
foreach ($file in $manifestFiles) {
    $relative = $file.FullName.Substring($repository.Length + 1).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedManifestLines += "$relative`t$($file.Length)`t$hash"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    $errors.Add('Missing SKILL_MANIFEST.tsv')
} else {
    $actualManifestLines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8)
    if ($actualManifestLines.Count -ne $expectedManifestLines.Count) {
        $errors.Add("Manifest row count mismatch: expected $($expectedManifestLines.Count), got $($actualManifestLines.Count)")
    } else {
        for ($index = 0; $index -lt $expectedManifestLines.Count; $index++) {
            if ($actualManifestLines[$index] -cne $expectedManifestLines[$index]) {
                $errors.Add("Manifest mismatch at line $($index + 1): SKILL_MANIFEST.tsv")
            }
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "PUBLIC_RELEASE_VALIDATION=FAIL ERRORS=$($errors.Count)"
}

Write-Output "PUBLIC_RELEASE_VALIDATION=PASS"
Write-Output "SKILLS=$($actualSkills.Count)"
Write-Output "FILES=$($allFiles.Count)"
Write-Output "MANIFEST_FILES=$($manifestFiles.Count)"
