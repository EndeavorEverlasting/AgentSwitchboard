#!/usr/bin/env python3
"""
Cursor cloud agent client for launching subagents from dispatch workflows.

This module provides a Python interface for launching Cursor cloud agent subagents
from within dispatch_lanes.py. It implements an orchestration-layer protocol where:

1. The client (dispatch_lanes.py) writes a launch request to a known location
2. The orchestrator (a parent cloud agent) monitors for requests
3. The orchestrator launches subagents using the Task tool
4. Results are written back for the client to consume

This design allows dispatch_lanes.py (running as a subprocess without Task tool access)
to trigger subagent launches via a parent cloud agent orchestrator.
"""

import json
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any


@dataclass
class SubagentLaunchRequest:
    """Request to launch a cloud agent subagent."""
    request_id: str
    prompt: str
    description: str
    timeout_seconds: int = 300


@dataclass
class SubagentLaunchResult:
    """Result from a subagent launch."""
    request_id: str
    status: str  # "completed", "failed", "timeout"
    agent_id: Optional[str] = None  # cloudAgentBcId
    dashboard_url: Optional[str] = None
    error: Optional[str] = None
    duration_seconds: Optional[float] = None


class CursorAgentClient:
    """
    Client for launching Cursor cloud agent subagents via orchestration layer.
    
    This client writes launch requests to a shared location and waits for results
    from an orchestrator process that has Task tool access.
    """
    
    def __init__(self, requests_dir: Optional[Path] = None, results_dir: Optional[Path] = None):
        """
        Initialize the client.
        
        Args:
            requests_dir: Directory for launch requests (default: /tmp/cursor-agent-requests)
            results_dir: Directory for launch results (default: /tmp/cursor-agent-results)
        """
        self.requests_dir = requests_dir or Path("/tmp/cursor-agent-requests")
        self.results_dir = results_dir or Path("/tmp/cursor-agent-results")
        
        # Create directories if they don't exist
        self.requests_dir.mkdir(parents=True, exist_ok=True)
        self.results_dir.mkdir(parents=True, exist_ok=True)
    
    def launch_subagent(
        self,
        prompt: str,
        description: str,
        timeout_seconds: int = 300,
        poll_interval: float = 2.0
    ) -> SubagentLaunchResult:
        """
        Launch a cloud agent subagent and wait for completion.
        
        Args:
            prompt: The prompt/task for the subagent
            description: Short description of what the subagent will do
            timeout_seconds: Maximum time to wait for subagent completion
            poll_interval: How often to check for results (seconds)
        
        Returns:
            SubagentLaunchResult with completion status and metadata
        """
        # Generate unique request ID
        request_id = f"req-{int(time.time() * 1000)}-{os.getpid()}"
        
        # Create launch request
        request = SubagentLaunchRequest(
            request_id=request_id,
            prompt=prompt,
            description=description,
            timeout_seconds=timeout_seconds
        )
        
        # Write request file
        request_file = self.requests_dir / f"{request_id}.json"
        with open(request_file, 'w') as f:
            json.dump({
                'request_id': request.request_id,
                'prompt': request.prompt,
                'description': request.description,
                'timeout_seconds': request.timeout_seconds,
                'submitted_at': datetime.now(timezone.utc).isoformat()
            }, f, indent=2)
        
        # Wait for result
        result_file = self.results_dir / f"{request_id}.json"
        start_time = time.time()
        
        while True:
            elapsed = time.time() - start_time
            
            if elapsed > timeout_seconds:
                return SubagentLaunchResult(
                    request_id=request_id,
                    status="timeout",
                    error=f"Orchestrator did not provide result within {timeout_seconds}s",
                    duration_seconds=elapsed
                )
            
            if result_file.exists():
                with open(result_file, 'r') as f:
                    result_data = json.load(f)
                
                return SubagentLaunchResult(
                    request_id=result_data['request_id'],
                    status=result_data['status'],
                    agent_id=result_data.get('agent_id'),
                    dashboard_url=result_data.get('dashboard_url'),
                    error=result_data.get('error'),
                    duration_seconds=result_data.get('duration_seconds')
                )
            
            time.sleep(poll_interval)


def detect_orchestration_support() -> Dict[str, Any]:
    """
    Detect if orchestration layer support is available.
    
    Returns:
        Dict with detection results including:
        - supported: bool
        - reason: str
        - details: dict
    """
    in_cloud_agent = os.environ.get("CURSOR_AGENT") == "1"
    agent_socket = os.environ.get("CURSOR_AGENT_SOCKET")
    
    if not in_cloud_agent:
        return {
            'supported': False,
            'reason': 'Not running in Cursor cloud agent context',
            'details': {
                'CURSOR_AGENT': os.environ.get("CURSOR_AGENT"),
                'required': 'CURSOR_AGENT=1'
            }
        }
    
    if not agent_socket or not Path(agent_socket).exists():
        return {
            'supported': False,
            'reason': 'Agent socket unavailable',
            'details': {
                'CURSOR_AGENT_SOCKET': agent_socket,
                'socket_exists': Path(agent_socket).exists() if agent_socket else False
            }
        }
    
    # Check if orchestrator process is running
    # For now, we assume if we're in a cloud agent with socket, orchestration MAY be available
    # The actual test is whether requests get processed
    return {
        'supported': True,
        'reason': 'Cloud agent context with socket available; orchestration layer may be active',
        'details': {
            'CURSOR_AGENT': '1',
            'CURSOR_AGENT_SOCKET': agent_socket,
            'socket_exists': True,
            'note': 'Orchestration requires active orchestrator process monitoring requests'
        }
    }
