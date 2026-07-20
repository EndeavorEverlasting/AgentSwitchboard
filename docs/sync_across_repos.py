#!/usr/bin/env python3
"""
Sync website files across repos.
Copies the prompt kit files to Triage, SysAdminSuite, and AgentSwitchboard docs folders.
"""

import shutil
import sys
from pathlib import Path

# Source directory (AgentSwitchboard docs)
SOURCE_DIR = Path(__file__).parent

# Target repos and their docs directories
TARGET_REPOS = {
    "web-excel-repair-triage": SOURCE_DIR.parent.parent / "web-excel-repair-triage" / "docs",
    "SysAdminSuite": SOURCE_DIR.parent.parent / "SysAdminSuite" / "docs",
    "AgentSwitchboard": SOURCE_DIR,  # Already in AgentSwitchboard
}

# Files to sync
SYNC_FILES = [
    "prompt-kit.html",
    "prompt-kit.js",
    "prompts.json",
    "reference.json",
    "AI_Harness_Prompt_Kit_v39.xlsx",
]


def sync_files(dry_run: bool = False) -> dict:
    """Sync files to all target repos."""
    results = {}
    
    for repo_name, target_dir in TARGET_REPOS.items():
        if repo_name == "AgentSwitchboard":
            results[repo_name] = {"status": "skipped", "reason": "source repo"}
            continue
        
        if not target_dir.parent.exists():
            results[repo_name] = {"status": "skipped", "reason": f"repo not found at {target_dir.parent}"}
            continue
        
        target_dir.mkdir(parents=True, exist_ok=True)
        
        copied = []
        for filename in SYNC_FILES:
            src = SOURCE_DIR / filename
            dst = target_dir / filename
            
            if src.exists():
                if not dry_run:
                    shutil.copy2(src, dst)
                copied.append(filename)
        
        results[repo_name] = {
            "status": "synced" if not dry_run else "dry_run",
            "files": copied,
            "target": str(target_dir),
        }
    
    return results


def main():
    """Main entry point."""
    dry_run = "--dry-run" in sys.argv
    
    print(f"Syncing website files {'(dry run)' if dry_run else ''}...")
    print(f"Source: {SOURCE_DIR}")
    print()
    
    results = sync_files(dry_run=dry_run)
    
    for repo_name, result in results.items():
        print(f"[{repo_name}]")
        print(f"  Status: {result['status']}")
        if "reason" in result:
            print(f"  Reason: {result['reason']}")
        if "files" in result:
            print(f"  Files: {len(result['files'])}")
            for f in result["files"]:
                print(f"    - {f}")
        if "target" in result:
            print(f"  Target: {result['target']}")
        print()
    
    print("Sync complete.")


if __name__ == "__main__":
    main()
