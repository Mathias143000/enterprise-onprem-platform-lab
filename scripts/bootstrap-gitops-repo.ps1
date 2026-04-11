param(
  [string]$BareRepoPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "artifacts\\git\\platform.git"),
  [string]$WorktreePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "artifacts\\git\\platform-worktree")
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$gitopsSource = Join-Path $repoRoot "flux"
$helmSource = Join-Path $repoRoot "helm"
$artifactsDir = Split-Path $BareRepoPath -Parent

New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
if (-not (Test-Path $BareRepoPath)) {
  & git init --bare $BareRepoPath | Out-Null
}

if (Test-Path $WorktreePath) {
  Remove-Item -Recurse -Force $WorktreePath
}
New-Item -ItemType Directory -Force -Path $WorktreePath | Out-Null
Copy-Item -Recurse -Force $gitopsSource (Join-Path $WorktreePath "flux")
Copy-Item -Recurse -Force $helmSource (Join-Path $WorktreePath "helm")

Push-Location $WorktreePath
try {
  & git init -b main | Out-Null
  & git config user.name "Portfolio GitOps Bot"
  & git config user.email "portfolio-gitops@example.local"
  & git add .
  & git commit -m "Bootstrap GitOps manifests" | Out-Null
  & git remote add origin $BareRepoPath
  & git push -f origin main | Out-Null
}
finally {
  Pop-Location
}

& git -C $BareRepoPath update-server-info
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
