#!/usr/bin/env python3
"""
Test script for cloud agent orchestration.

This script demonstrates the orchestration flow by:
1. Running dispatch_lanes.py in a background thread
2. Monitoring for subagent launch requests
3. Simulating orchestrator behavior (in real usage, the cloud agent would use Task tool)
4. Writing mock results for testing
"""

import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path


def monitor_and_respond_to_requests(requests_dir, results_dir, timeout=10):
    """
    Monitor requests directory and write mock responses.
    
    In real usage, this would launch subagents via Task tool.
    For testing, we write mock successful responses.
    """
    print(f"[Orchestrator] Monitoring {requests_dir} for requests...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        # Check for request files
        request_files = list(requests_dir.glob("*.json"))
        
        for request_file in request_files:
            print(f"[Orchestrator] Found request: {request_file.name}")
            
            try:
                with open(request_file, 'r') as f:
                    request = json.load(f)
                
                request_id = request['request_id']
                prompt = request['prompt']
                
                print(f"[Orchestrator] Processing request {request_id}")
                print(f"[Orchestrator] Prompt: {prompt[:100]}...")
                
                # Simulate subagent launch delay
                time.sleep(1)
                
                # Write mock result
                result = {
                    'request_id': request_id,
                    'status': 'completed',
                    'agent_id': f'bc-mock-{request_id}',
                    'dashboard_url': f'https://cursor.com/agents/bc-mock-{request_id}',
                    'error': None,
                    'duration_seconds': 1.0,
                    'completed_at': datetime.now(timezone.utc).isoformat(),
                    'note': 'Mock result for testing - in real usage, would launch via Task tool'
                }
                
                result_file = results_dir / f"{request_id}.json"
                with open(result_file, 'w') as f:
                    json.dump(result, f, indent=2)
                
                print(f"[Orchestrator] Wrote result to {result_file.name}")
                
                # Delete request file
                request_file.unlink()
                print(f"[Orchestrator] Deleted request {request_file.name}")
                
            except Exception as e:
                print(f"[Orchestrator] Error processing {request_file.name}: {e}")
        
        time.sleep(0.5)
    
    print("[Orchestrator] Monitoring timeout reached")


def main():
    if len(sys.argv) < 3:
        print("Usage: test_cloud_agent_orchestration.py <manifest_path> <output_dir>")
        sys.exit(1)
    
    manifest_path = sys.argv[1]
    output_dir = sys.argv[2]
    
    requests_dir = Path("/tmp/cursor-agent-requests")
    results_dir = Path("/tmp/cursor-agent-results")
    
    # Clean up old requests/results
    for f in requests_dir.glob("*.json"):
        f.unlink()
    for f in results_dir.glob("*.json"):
        f.unlink()
    
    # Start orchestrator in background thread
    orchestrator_thread = threading.Thread(
        target=monitor_and_respond_to_requests,
        args=(requests_dir, results_dir, 30),
        daemon=True
    )
    orchestrator_thread.start()
    
    # Give orchestrator time to start
    time.sleep(0.5)
    
    # Run dispatch_lanes.py
    script_dir = Path(__file__).parent
    dispatch_script = script_dir / "dispatch_lanes.py"
    
    print(f"[Main] Running dispatch_lanes.py...")
    print(f"[Main] Manifest: {manifest_path}")
    print(f"[Main] Output: {output_dir}")
    print()
    
    result = subprocess.run(
        ["python3", str(dispatch_script), manifest_path, output_dir],
        capture_output=False
    )
    
    print()
    print(f"[Main] Dispatch exited with code {result.returncode}")
    
    # Wait for orchestrator thread
    orchestrator_thread.join(timeout=2)
    
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
