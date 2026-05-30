# Create repo on GitHub (nimishadeepak10) and push main.
# Run once after: gh auth login

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Program Files\GitHub CLI;" + $env:PATH

Set-Location $PSScriptRoot

gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host "Run 'gh auth login' first, then run this script again."
    exit 1
}

gh repo create AXI4Lite_Formal-Ver --public --source=. --remote=origin --push
Write-Host "Done: https://github.com/nimishadeepak10/AXI4Lite_Formal-Ver"
