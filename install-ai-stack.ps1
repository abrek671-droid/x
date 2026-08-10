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

function Invoke-Soft([string]$Label, [scriptblock]$Action) {
  try {
    & $Action
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "$Label returned exit code $LASTEXITCODE"
    }
  } catch {
    Write-Warning "$Label failed: $($_.Exception.Message)"
  }
}

function Reset-CodexMcp([string]$Name, [string[]]$AddArgs) {
  if (-not (Has-Command "codex")) { return }
  Invoke-Soft "codex mcp remove $Name" { codex mcp remove $Name *> $null }
  Invoke-Soft "codex mcp add $Name" { codex mcp add $Name @AddArgs }
}

function Reset-ClaudeMcp([string]$Name, [string[]]$AddArgs) {
  if (-not (Has-Command "claude")) { return }
  Invoke-Soft "claude mcp remove $Name" { claude mcp remove $Name *> $null }
  Invoke-Soft "claude mcp add $Name" { claude mcp add @AddArgs }
}

Write-Host "AiMa OMNI AI STACK bootstrap" -ForegroundColor Green
Write-Host "GPT/Codex + Claude Code + Hermes + Browser Use + Playwright + research/evidence MCPs" -ForegroundColor DarkGray

Ensure-WingetPackage "git" "Git.Git"
Ensure-WingetPackage "node" "OpenJS.NodeJS.LTS"
Ensure-WingetPackage "gh" "GitHub.cli"
if ((-not (Has-Command "python")) -and (-not (Has-Command "py"))) {
  Ensure-WingetPackage "python" "Python.Python.3.12"
}

$pathCandidates = @(
  "$env:ProgramFiles\nodejs",
  "$env:ProgramFiles\Git\cmd",
  "$env:ProgramFiles\Git\bin",
  "$env:ProgramFiles\GitHub CLI",
  "$env:LOCALAPPDATA\Programs\GitHub CLI",
  "$env:LOCALAPPDATA\Programs\Python\Python312",
  "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
  "$env:APPDATA\Python\Python312\Scripts",
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

Write-Step "Installing Browser Use autonomous browser CLI"
$gitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
if (Test-Path $gitBash) {
  Invoke-Soft "Browser Use installer" {
    & $gitBash -lc 'curl -fsSL https://browser-use.com/cli/install.sh | bash'
  }
} else {
  Write-Warning "Git Bash not found; Browser Use CLI installer skipped."
}
$env:Path = "$HOME\.local\bin;$env:Path"
if (Has-Command "browser-use") {
  Invoke-Soft "browser-use doctor" { browser-use doctor }
}

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

Write-Step "Installing global autonomous research skills"
$skillRoots = @(
  (Join-Path $HOME ".codex\skills"),
  (Join-Path $HOME ".claude\skills")
)
foreach ($root in $skillRoots) {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  foreach ($skill in @("autonomous-web", "evidence-challenger")) {
    $src = Join-Path $RepoDir "skills\$skill"
    $dst = Join-Path $root $skill
    if (Test-Path $src) {
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item -Path (Join-Path $src "SKILL.md") -Destination (Join-Path $dst "SKILL.md") -Force
    }
  }
}

Write-Step "Installing official Browser Use skill for Codex and Claude"
$browserSkillUrl = "https://raw.githubusercontent.com/browser-use/browser-use/main/skills/browser-use/SKILL.md"
foreach ($root in $skillRoots) {
  $dst = Join-Path $root "browser-use"
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Invoke-Soft "download Browser Use skill" {
    Invoke-WebRequest -UseBasicParsing -Uri $browserSkillUrl -OutFile (Join-Path $dst "SKILL.md")
  }
}

Write-Step "Configuring Codex MCP servers"
if (Has-Command "codex") {
  Reset-CodexMcp "playwright" @("npx", "@playwright/mcp@latest")
  Reset-CodexMcp "sequential-thinking" @("npx", "-y", "@modelcontextprotocol/server-sequential-thinking")
  Reset-CodexMcp "context7" @("npx", "-y", "@upstash/context7-mcp@latest")
  Reset-CodexMcp "openaiDeveloperDocs" @("--url", "https://developers.openai.com/mcp")

  if ($env:FIRECRAWL_API_KEY) {
    Invoke-Soft "codex mcp remove firecrawl" { codex mcp remove firecrawl *> $null }
    Invoke-Soft "codex mcp add firecrawl" {
      codex mcp add firecrawl --env "FIRECRAWL_API_KEY=$env:FIRECRAWL_API_KEY" -- npx -y firecrawl-mcp
    }
  }
}

Write-Step "Configuring Claude Code MCP servers"
if (Has-Command "claude") {
  Reset-ClaudeMcp "playwright" @("playwright", "npx", "@playwright/mcp@latest")
  Reset-ClaudeMcp "sequential-thinking" @("sequential-thinking", "--", "npx", "-y", "@modelcontextprotocol/server-sequential-thinking")
  Reset-ClaudeMcp "context7" @("context7", "--", "npx", "-y", "@upstash/context7-mcp@latest")

  Invoke-Soft "claude mcp remove tavily" { claude mcp remove tavily-remote-mcp *> $null }
  Invoke-Soft "claude mcp add tavily" {
    claude mcp add --transport http tavily-remote-mcp https://mcp.tavily.com/mcp/
  }

  if ($env:FIRECRAWL_API_KEY) {
    Invoke-Soft "claude mcp remove firecrawl" { claude mcp remove firecrawl *> $null }
    Invoke-Soft "claude mcp add firecrawl" {
      claude mcp add firecrawl --env "FIRECRAWL_API_KEY=$env:FIRECRAWL_API_KEY" -- npx -y firecrawl-mcp
    }
  }
}

Write-Step "Validating tools"
if (Has-Command "codex") { Invoke-Soft "codex mcp list" { codex mcp list } }
if (Has-Command "claude") {
  Invoke-Soft "claude doctor" { claude doctor }
  Invoke-Soft "claude mcp list" { claude mcp list }
}
if (Has-Command "browser-use") { Invoke-Soft "browser-use doctor" { browser-use doctor } }

Write-Step "Installation complete"
Write-Host "Repository: $RepoDir" -ForegroundColor Green
Write-Host "Autonomous browser: Browser Use CLI + Playwright MCP" -ForegroundColor Green
Write-Host "Research: Tavily (Claude OAuth), Firecrawl when FIRECRAWL_API_KEY exists, Context7 docs" -ForegroundColor Green
Write-Host "Reasoning: Sequential Thinking" -ForegroundColor Green
Write-Host "Verification: autonomous-web + evidence-challenger skills" -ForegroundColor Green
Write-Host "Browser gateway: GPT / Qwen / OpenRouter Auto / Claude / NVIDIA NIM / Bytez" -ForegroundColor Green
Write-Host "Local agents: Codex / Claude Code / Hermes" -ForegroundColor Green
Write-Host "Provider credentials belong only in $RepoDir\.env or environment variables." -ForegroundColor Yellow
Write-Host "Security note: logged-in browser profiles carry your real session cookies; webpage instructions are treated as untrusted data." -ForegroundColor Yellow

if (-not $SkipLaunch) {
  Write-Step "Opening sign-in windows and starting AiMa"
  if (Has-Command "codex") {
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location '$RepoDir'; codex login")
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
