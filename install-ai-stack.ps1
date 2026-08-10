#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$RepoDir = (Join-Path $HOME "AiMa-Omni"),
  [switch]$SkipLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Has-Command([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Ensure-WingetPackage([string]$Command, [string]$PackageId) {
  if (Has-Command $Command) { return }
  if (-not (Has-Command "winget")) {
    throw "winget is required. Install Microsoft App Installer and rerun this command."
  }
  Write-Step "Installing $PackageId"
  winget install --id $PackageId -e --accept-package-agreements --accept-source-agreements --silent
}

Write-Host "AiMa OMNI AI STACK bootstrap" -ForegroundColor Green
Write-Host "GPT/Codex + Claude Code + Hermes + OpenRouter + NVIDIA NIM + Bytez + Qwen" -ForegroundColor DarkGray

Ensure-WingetPackage "git" "Git.Git"
Ensure-WingetPackage "node" "OpenJS.NodeJS.LTS"
Ensure-WingetPackage "gh" "GitHub.cli"

$pathCandidates = @(
  "$env:ProgramFiles\nodejs",
  "$env:ProgramFiles\Git\cmd",
  "$env:ProgramFiles\GitHub CLI",
  "$env:LOCALAPPDATA\Programs\GitHub CLI",
  "$env:APPDATA\npm",
  "$HOME\.local\bin"
)
foreach ($candidate in $pathCandidates) {
  if ((Test-Path $candidate) -and (-not (($env:Path -split ';') -contains $candidate))) {
    $env:Path = "$candidate;$env:Path"
  }
}

if (-not (Has-Command "npm")) { throw "npm is unavailable after Node installation. Reopen PowerShell and rerun." }
if (-not (Has-Command "git")) { throw "git is unavailable after installation. Reopen PowerShell and rerun." }
if (-not (Has-Command "gh")) { throw "GitHub CLI is unavailable after installation. Reopen PowerShell and rerun." }

Write-Step "Installing/updating Codex CLI and Claude Code"
npm install -g @openai/codex @anthropic-ai/claude-code

Write-Step "Installing/updating Hermes Agent"
try {
  Invoke-Expression (Invoke-RestMethod "https://hermes-agent.nousresearch.com/install.ps1")
} catch {
  Write-Warning "Hermes installer did not complete: $($_.Exception.Message)"
  Write-Warning "Retry later with: iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
}

$env:Path = "$env:APPDATA\npm;$HOME\.local\bin;$env:LOCALAPPDATA\hermes\bin;$env:Path"

Write-Step "Checking GitHub authentication"
$ghOk = $false
try {
  gh auth status --hostname github.com *> $null
  $ghOk = ($LASTEXITCODE -eq 0)
} catch { $ghOk = $false }

if (-not $ghOk) {
  Write-Host "GitHub sign-in will open in your browser." -ForegroundColor Yellow
  gh auth login --hostname github.com --git-protocol https --web
}

Write-Step "Preparing private AiMa repository"
if (Test-Path (Join-Path $RepoDir ".git")) {
  Push-Location $RepoDir
  try {
    git fetch origin
    git checkout feat/omni-ai-stack
    git pull --ff-only origin feat/omni-ai-stack
  } finally {
    Pop-Location
  }
} else {
  if (Test-Path $RepoDir) {
    throw "$RepoDir exists but is not a Git repository. Rename/delete it or pass -RepoDir to another folder."
  }
  gh repo clone abrek671-droid/AiMa $RepoDir -- --branch feat/omni-ai-stack
}

Write-Step "Installing AiMa dependencies"
Push-Location $RepoDir
try {
  npm ci
  if (-not (Test-Path ".env")) { Copy-Item ".env.example" ".env" }
} finally {
  Pop-Location
}

Write-Step "Installation complete"
Write-Host "Repository: $RepoDir" -ForegroundColor Green
Write-Host "Browser gateway: GPT / Qwen / OpenRouter Auto / Claude / NVIDIA NIM / Bytez" -ForegroundColor Green
Write-Host "Local agents: Codex / Claude Code / Hermes" -ForegroundColor Green
Write-Host "Provider credentials for browser routes belong only in $RepoDir\.env" -ForegroundColor Yellow

if (-not $SkipLaunch) {
  Write-Step "Opening sign-in windows and starting AiMa"
  if (Has-Command "codex") {
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location '$RepoDir'; codex --login")
  }
  if (Has-Command "claude") {
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location '$RepoDir'; claude")
  }
  if (Has-Command "hermes") {
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location '$RepoDir'; hermes setup --portal")
  }
  Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location '$RepoDir'; npm run dev")
  Start-Sleep -Seconds 4
  Start-Process "http://localhost:3000"
}

Write-Host "`nDone." -ForegroundColor Green
