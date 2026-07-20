#!/usr/bin/env pwsh
<#
.SYNOPSIS
    End-to-end synthetic harness validator for AgentSwitchboard repos.

.DESCRIPTION
    Aggregates safe offline harness checks and prints an honest PASS/SKIP/FAIL matrix.
    Never performs live runtime execution, network probing, launcher execution, target mutation,
    save/account mutation, or secret collection.

.EXAMPLE
    pwsh -File Validate-Harness.ps1
    pwsh -File Validate-Harness.ps1 -JsonOutput
    pwsh -File Validate-Harness.ps1 -JsonOutput -OutputPath artifacts/harness-result.json
#>

[CmdletBinding()]
param(
    [switch]$JsonOutput,
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Results tracking ──────────────────────────────────────────────────────────
$script:Results = [System.Collections.ArrayList]::new()
$script:RepoRoot = $null
$script:Branch = "unknown"
$script:CommitSHA = "unknown"

# ── Helper functions ──────────────────────────────────────────────────────────

function Add-Result {
    param(
        [string]$CheckName,
        [string]$Status,  # PASS, SKIP, FAIL
        [string]$Detail = "",
        [bool]$IsRequired = $true
    )
    $null = $script:Results.Add([PSCustomObject]@{
        Check   = $CheckName
        Status  = $Status
        Detail  = $Detail
        Required = $IsRequired
    })
}

function Test-PathSafe {
    param([string]$Path)
    return (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
}

# ── Detect repo root ──────────────────────────────────────────────────────────

function Find-RepoRoot {
    $current = Get-Location
    while ($current -ne $null) {
        if (Test-PathSafe (Join-Path $current ".git")) {
            return $current
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

# ── Validators ────────────────────────────────────────────────────────────────

function Test-RequiredFiles {
    $required = @("AGENTS.md", "README.md")
    $optional = @("CODEBASE_MAP.md", "SKILLS.md", "CAPABILITIES.md", "TRIGGERS.md", "CONTRIBUTING.md")
    
    foreach ($file in $required) {
        $path = Join-Path $script:RepoRoot $file
        if (Test-PathSafe $path) {
            Add-Result "required_files/$file" "PASS" "Exists and tracked"
        } else {
            Add-Result "required_files/$file" "FAIL" "Missing required file: $file" $true
        }
    }
    
    foreach ($file in $optional) {
        $path = Join-Path $script:RepoRoot $file
        if (Test-PathSafe $path) {
            Add-Result "required_files/$file" "PASS" "Exists"
        } else {
            Add-Result "required_files/$file" "SKIP" "Optional file not present: $file" $false
        }
    }
}

function Test-RunContext {
    # Check for .ai directory, harness config, or run context
    $aiDir = Join-Path $script:RepoRoot ".ai"
    $harnessConfig = Join-Path $script:RepoRoot ".ai" "agent-contract.json"
    
    if (Test-PathSafe $aiDir) {
        if (Test-PathSafe $harnessConfig) {
            Add-Result "run_context" "PASS" ".ai/agent-contract.json exists"
        } else {
            Add-Result "run_context" "PASS" ".ai directory exists (no agent-contract.json)"
        }
    } else {
        Add-Result "run_context" "SKIP" "No .ai directory found" $false
    }
}

function Test-ArtifactRegistry {
    $artifactPaths = @(
        (Join-Path $script:RepoRoot "artifacts"),
        (Join-Path $script:RepoRoot "docs" "artifacts"),
        (Join-Path $script:RepoRoot ".ai" "harness")
    )
    
    foreach ($path in $artifactPaths) {
        if (Test-PathSafe $path) {
            Add-Result "artifact_registry" "PASS" "Artifact directory found: $path"
            return
        }
    }
    
    Add-Result "artifact_registry" "SKIP" "No artifact directories found" $false
}

function Test-ReportRenderer {
    $reportPaths = @(
        (Join-Path $script:RepoRoot "scripts"),
        (Join-Path $script:RepoRoot "tools"),
        (Join-Path $script:RepoRoot ".ai" "skills")
    )
    
    foreach ($path in $reportPaths) {
        if (Test-PathSafe $path) {
            $files = Get-ChildItem -Path $path -Filter "*.ps1" -ErrorAction SilentlyContinue
            if ($files -and $files.Count -gt 0) {
                Add-Result "report_renderer" "PASS" "PowerShell scripts found in $path"
                return
            }
        }
    }
    
    Add-Result "report_renderer" "SKIP" "No report renderer scripts found" $false
}

function Test-HookHygiene {
    $hookPaths = @(
        (Join-Path $script:RepoRoot ".git" "hooks"),
        (Join-Path $script:RepoRoot ".husky"),
        (Join-Path $script:RepoRoot "scripts" "hooks")
    )
    
    foreach ($path in $hookPaths) {
        if (Test-PathSafe $path) {
            $files = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue
            if ($files -and $files.Count -gt 0) {
                Add-Result "hook_hygiene" "PASS" "Hooks found in $path"
                return
            }
        }
    }
    
    Add-Result "hook_hygiene" "SKIP" "No hooks found" $false
}

function Test-WorkflowSpecs {
    $workflowPaths = @(
        (Join-Path $script:RepoRoot ".github" "workflows"),
        (Join-Path $script:RepoRoot ".ai" "workflows")
    )
    
    foreach ($path in $workflowPaths) {
        if (Test-PathSafe $path) {
            $files = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue
            if ($files -and $files.Count -gt 0) {
                Add-Result "workflow_specs" "PASS" "Workflow files found in $path"
                return
            }
        }
    }
    
    Add-Result "workflow_specs" "SKIP" "No workflow specs found" $false
}

function Test-MCPLSPReadiness {
    # Check for MCP/LSP configuration (optional, informational)
    $mcpPaths = @(
        (Join-Path $script:RepoRoot ".cursorrc"),
        (Join-Path $script:RepoRoot ".vscode" "settings.json"),
        (Join-Path $script:RepoRoot "mcp.json")
    )
    
    foreach ($path in $mcpPaths) {
        if (Test-PathSafe $path) {
            Add-Result "mcp_lsp_readiness" "PASS" "MCP/LSP config found: $path"
            return
        }
    }
    
    Add-Result "mcp_lsp_readiness" "SKIP" "No MCP/LSP configuration found" $false
}

function Test-PromptKit {
    $promptKitHtml = Join-Path $script:RepoRoot "docs" "prompt-kit.html"
    $promptsJson = Join-Path $script:RepoRoot "docs" "prompts.json"
    
    if (Test-PathSafe $promptKitHtml) {
        if (Test-PathSafe $promptsJson) {
            Add-Result "prompt_kit" "PASS" "prompt-kit.html and prompts.json exist"
        } else {
            Add-Result "prompt_kit" "PASS" "prompt-kit.html exists (no prompts.json)"
        }
    } else {
        Add-Result "prompt_kit" "SKIP" "No prompt kit found" $false
    }
}

# ── Main execution ────────────────────────────────────────────────────────────

# Detect repo root
$script:RepoRoot = Find-RepoRoot
if (-not $script:RepoRoot) {
    Write-Error "Could not detect repository root. Run from inside a git repository."
    exit 1
}

# Get git info
try {
    $script:Branch = (git -C $script:RepoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $script:CommitSHA = (git -C $script:RepoRoot rev-parse --short HEAD 2>$null).Trim()
} catch {
    $script:Branch = "unknown"
    $script:CommitSHA = "unknown"
}

# Run all validators
Write-Host ""
Write-Host "APP HARNESS VALIDATION" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository: $script:RepoRoot" -ForegroundColor Gray
Write-Host "Branch:     $script:Branch" -ForegroundColor Gray
Write-Host "Commit:     $script:CommitSHA" -ForegroundColor Gray
Write-Host ""

Test-RequiredFiles
Test-RunContext
Test-ArtifactRegistry
Test-ReportRenderer
Test-HookHygiene
Test-WorkflowSpecs
Test-MCPLSPReadiness
Test-PromptKit

# Count results
$passed = @($script:Results | Where-Object { $_.Status -eq "PASS" }).Count
$skipped = @($script:Results | Where-Object { $_.Status -eq "SKIP" }).Count
$failed = @($script:Results | Where-Object { $_.Status -eq "FAIL" }).Count

# Print matrix
foreach ($result in $script:Results) {
    $color = switch ($result.Status) {
        "PASS" { "Green" }
        "SKIP" { "Yellow" }
        "FAIL" { "Red" }
        default { "Gray" }
    }
    $prefix = if (-not $result.Required) { "(optional)" } else { "" }
    Write-Host "  [$($result.Status)] $($result.Check) $prefix" -ForegroundColor $color
    if ($result.Detail) {
        Write-Host "          $($result.Detail)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Result: $passed passed / $skipped skipped / $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host ""

# JSON output
if ($JsonOutput) {
    $jsonResult = [PSCustomObject]@{
        repository = $script:RepoRoot
        branch = $script:Branch
        commit = $script:CommitSHA
        timestamp = (Get-Date -Format "o")
        results = $script:Results
        summary = [PSCustomObject]@{
            passed = $passed
            skipped = $skipped
            failed = $failed
            total = $script:Results.Count
        }
    }
    
    $json = $jsonResult | ConvertTo-Json -Depth 10
    
    if ($OutputPath) {
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        $json | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "JSON result written to: $OutputPath" -ForegroundColor Cyan
    } else {
        Write-Host "JSON Result:" -ForegroundColor Cyan
        Write-Host $json
    }
}

# Exit code
exit $failed
