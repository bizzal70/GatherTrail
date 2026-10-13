<#
.SYNOPSIS
  Publishes this folder to GitHub without keeping a local .git folder.
  Runs the tests first and refuses to publish if they fail. Then clones the
  repo to a temp folder, mirrors the project files into it, commits, pushes,
  and deletes the temp clone.

  With -Tag, also tags the commit. A tag starting with "v" makes GitHub
  build a release: a zip of the addon, uploaded to CurseForge and Wago once
  their tokens and project IDs are in place (see README, "Releasing").

.EXAMPLE
  .\tools\Publish.ps1 -Message "Fix the position option"
  .\tools\Publish.ps1 -Message "Release 0.2.0" -Tag v0.2.0
#>
param(
    [string]$Message = "Update",
    [string]$Repo = "bizzal70/GatherTrail",
    [string]$Tag,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent

if (-not $SkipTests) {
    # The tests need the "lupa" Python package (pip install lupa).
    $output = & python (Join-Path $root "tests\run.py")
    if ($LASTEXITCODE -ne 0) {
        $output | Where-Object { $_ -cmatch "ERROR:|CHECK FAILED" } | ForEach-Object { Write-Host $_ }
        throw "Tests failed or could not run, so nothing was published. Run 'python tests\run.py' to see why."
    }
    Write-Host "Tests passed."
}

$tmp = Join-Path $env:TEMP ("gathertrail-publish-" + [guid]::NewGuid().ToString("N"))

try {
    gh repo clone $Repo $tmp
    if ($LASTEXITCODE -ne 0) { throw "Clone failed" }

    robocopy $root $tmp /MIR /XD .git .claude /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

    git -C $tmp checkout -q -B main
    git -C $tmp add -A
    if (git -C $tmp status --porcelain) {
        git -C $tmp commit -q -m $Message
        if ($LASTEXITCODE -ne 0) { throw "Commit failed" }
        git -C $tmp push -q -u origin main
        if ($LASTEXITCODE -ne 0) { throw "Push failed" }
        Write-Host "Published to https://github.com/$Repo"
    }
    else {
        Write-Host "Nothing new to publish."
    }

    if ($Tag) {
        git -C $tmp tag $Tag
        if ($LASTEXITCODE -ne 0) { throw "Could not create tag $Tag (does it already exist?)" }
        git -C $tmp push -q origin $Tag
        if ($LASTEXITCODE -ne 0) { throw "Could not push tag $Tag" }
        Write-Host "Tagged $Tag"
    }
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
}
