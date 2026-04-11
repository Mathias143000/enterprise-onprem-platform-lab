param(
  [Parameter(Mandatory = $true)][string]$Message
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$worktreePath = Join-Path $repoRoot "artifacts\\git\\platform-worktree"
$bareRepoPath = Join-Path $repoRoot "artifacts\\git\\platform.git"
$sourceGitopsPath = Join-Path $repoRoot "flux"
$sourceHelmPath = Join-Path $repoRoot "helm"

if (-not (Test-Path $worktreePath)) {
  throw "GitOps worktree not found. Run bootstrap-gitops-repo.ps1 first."
}

if (Test-Path (Join-Path $worktreePath "flux")) {
  Remove-Item -Recurse -Force (Join-Path $worktreePath "flux")
}
if (Test-Path (Join-Path $worktreePath "helm")) {
  Remove-Item -Recurse -Force (Join-Path $worktreePath "helm")
}
Copy-Item -Recurse -Force $sourceGitopsPath (Join-Path $worktreePath "flux")
Copy-Item -Recurse -Force $sourceHelmPath (Join-Path $worktreePath "helm")

Push-Location $worktreePath
try {
  & git add .
  $status = & git status --porcelain
  if (-not $status) {
    Write-Host "No GitOps changes to push."
    exit 0
  }
  & git commit -m $Message | Out-Null
  & git push origin main | Out-Null
}
finally {
  Pop-Location
}

& git -C $bareRepoPath update-server-info
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
