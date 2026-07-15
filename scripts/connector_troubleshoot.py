#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Connector Troubleshooting Script
Automatically checks all log-collector-master pods and generates reports for all connectors.
Compatible with Python 2.7 and Python 3.x
"""

from __future__ import print_function
import subprocess
import sys
import json
import re
from datetime import datetime, timedelta

class Color:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text):
    """Print a formatted header"""
    print("\n" + Color.BOLD + Color.BLUE + "=" * 80 + Color.END)
    print(Color.BOLD + Color.BLUE + text.center(80) + Color.END)
    print(Color.BOLD + Color.BLUE + "=" * 80 + Color.END + "\n")

def print_section(text):
    """Print a formatted section header"""
    print("\n" + Color.CYAN + Color.BOLD + text + Color.END)
    print(Color.CYAN + "-" * len(text) + Color.END)

def run_command(command, capture_output=True):
    """
    Execute a shell command and return status, stdout, stderr
    Returns: (returncode, stdout, stderr)
    """
    try:
        process = subprocess.Popen(
            command,
            shell=True,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None
        )
        stdout, stderr = process.communicate()
        
        # Convert bytes to string for Python 3 compatibility
        if sys.version_info[0] >= 3:
            stdout = stdout.decode('utf-8') if stdout else ""
            stderr = stderr.decode('utf-8') if stderr else ""
        else:
            stdout = stdout if stdout else ""
            stderr = stderr if stderr else ""
        
        return process.returncode, stdout, stderr
    except Exception as e:
        return -1, "", str(e)

def parse_timestamp(line):
    """Extract and parse timestamp from log line"""
    try:
        # Format: 2024-03-08 19:20:09,038
        match = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
        if match:
            return datetime.strptime(match.group(1), '%Y-%m-%d %H:%M:%S')
    except:
        pass
    return None

def get_log_collector_pods():
    """
    Retrieve all log-collector-master pods
    Returns: list of pod names
    """
    print_section("Fetching log-collector-master pods...")
    
    returncode, stdout, stderr = run_command("kubectl get pods | grep log-collector-master")
    
    if returncode != 0:
        print(Color.RED + "Error fetching pods: " + stderr + Color.END)
        return []
    
    pods = []
    for line in stdout.strip().split('\n'):
        if line:
            pod_name = line.split()[0]
            pods.append(pod_name)
    
    print(Color.GREEN + "Found " + str(len(pods)) + " log-collector-master pod(s)" + Color.END)
    for idx, pod in enumerate(pods, 1):
        print("  " + str(idx) + ". " + pod)
    
    return pods

def get_connector_logs(pod):
    """
    Get list of connector logs from a specific pod (only .log files)
    Returns: list of log file names
    """
    command = "kubectl exec -it {0} -- ls logs/ 2>/dev/null".format(pod)
    returncode, stdout, stderr = run_command(command)
    
    if returncode != 0:
        print(Color.RED + "  Error accessing logs directory: " + stderr + Color.END)
        return []
    
    # Filter for .log files only (excludes .gz and other archived files)
    logs = [log.strip() for log in stdout.strip().split('\n') 
            if log.strip() and log.strip().endswith('.log')]
    return logs

def analyze_log_file(pod, log_file):
    """
    Analyze a connector log file and extract key information
    Returns: dict with analysis results
    """
    # Get last 200 lines for better analysis
    command = "kubectl exec -it {0} -- tail -n 200 logs/{1} 2>/dev/null".format(pod, log_file)
    returncode, stdout, stderr = run_command(command)
    
    analysis = {
        "connector": log_file,
        "accessible": returncode == 0,
        "error_count": 0,
        "warning_count": 0,
        "auth_failures": 0,
        "connection_errors": 0,
        "http_errors": {},
        "last_timestamp": None,
        "last_activity": "N/A",
        "status": "UNKNOWN",
        "issue_summary": [],
        "exceptions": []
    }
    
    if returncode != 0:
        analysis["status"] = "INACCESSIBLE"
        return analysis
    
    lines = stdout.split('\n')
    
    # Authentication failure patterns
    auth_patterns = [
        'failed to login', 'authentication failed', 'invalid client secret',
        'unauthorized_client', 'invalid access key', 'signatureDoesNotMatch',
        'invalid token', 'expired token', 'account has been disabled',
        'insufficient permissions'
    ]
    
    # Connection issue patterns
    connection_patterns = [
        'max retries exceeded', 'failed to establish', 'connection error',
        'sslerror', 'timeout', 'no such host', 'name or service not known'
    ]
    
    # Exception types
    exception_patterns = [
        'RuntimeError', 'AttributeError', 'KeyError', 'JSONDecodeError',
        'ConnectionError', 'Exception in'
    ]
    
    # Track HTTP error codes from summaries
    http_error_pattern = re.compile(r"'http_code': (\d+)")
    
    # Track unique issues
    seen_issues = set()
    
    for line in lines:
        line_lower = line.lower()
        
        # Extract timestamp
        ts = parse_timestamp(line)
        if ts and (not analysis["last_timestamp"] or ts > analysis["last_timestamp"]):
            analysis["last_timestamp"] = ts
            analysis["last_activity"] = line[:100] + "..." if len(line) > 100 else line
        
        # Count log levels
        if '|ERROR|' in line:
            analysis["error_count"] += 1
        elif '|WARNING|' in line:
            analysis["warning_count"] += 1
        
        # Authentication failures
        if any(pattern in line_lower for pattern in auth_patterns):
            analysis["auth_failures"] += 1
            # Extract concise error message
            if '|ERROR|' in line or '|WARNING|' in line:
                parts = line.split('|', 3)
                if len(parts) >= 4:
                    msg = parts[3][:150]
                    if msg not in seen_issues:
                        seen_issues.add(msg)
                        analysis["issue_summary"].append("AUTH: " + msg)
        
        # Connection errors
        if any(pattern in line_lower for pattern in connection_patterns):
            analysis["connection_errors"] += 1
            if len(analysis["issue_summary"]) < 5:
                parts = line.split('|', 3)
                if len(parts) >= 4:
                    msg = parts[3][:150]
                    if msg not in seen_issues:
                        seen_issues.add(msg)
                        analysis["issue_summary"].append("CONN: " + msg)
        
        # Exception tracking
        if any(pattern in line for pattern in exception_patterns):
            if len(analysis["exceptions"]) < 3:
                analysis["exceptions"].append(line.strip()[:200])
        
        # Extract HTTP codes from Content of summary
        if "'http_code':" in line:
            for match in http_error_pattern.finditer(line):
                code = int(match.group(1))
                if code >= 400:  # Only track error codes
                    analysis["http_errors"][code] = analysis["http_errors"].get(code, 0) + 1
    
    # Check for stale logs (no activity in last 7 days)
    is_stale = False
    if analysis["last_timestamp"]:
        days_old = (datetime.now() - analysis["last_timestamp"]).days
        if days_old > 7:
            is_stale = True
            analysis["issue_summary"].insert(0, "STALE: No activity for {0} days".format(days_old))
    
    # Determine status based on analysis
    if is_stale:
        analysis["status"] = "STALE"
    elif analysis["auth_failures"] > 3:
        analysis["status"] = "AUTH_FAILURE"
    elif analysis["connection_errors"] > 5:
        analysis["status"] = "CONNECTION_ERROR"
    elif analysis["error_count"] > 20:
        analysis["status"] = "CRITICAL"
    elif analysis["error_count"] > 5:
        analysis["status"] = "ERROR"
    elif analysis["warning_count"] > 10:
        analysis["status"] = "WARNING"
    elif analysis["error_count"] == 0 and analysis["warning_count"] <= 5:
        analysis["status"] = "HEALTHY"
    else:
        analysis["status"] = "DEGRADED"
    
    return analysis

def generate_pod_report(pod):
    """
    Generate a comprehensive report for a single pod
    Returns: dict with pod report
    """
    print_section("Analyzing pod: " + pod)
    
    logs = get_connector_logs(pod)
    
    if not logs:
        print(Color.YELLOW + "  No connector logs found or unable to access logs directory" + Color.END)
        return {"pod": pod, "connectors": [], "total_connectors": 0}
    
    print(Color.GREEN + "  Found " + str(len(logs)) + " connector log(s)" + Color.END)
    
    connector_analyses = []
    
    for idx, log_file in enumerate(logs, 1):
        sys.stdout.write("  Analyzing {0}/{1}: {2}...\r".format(idx, len(logs), log_file))
        sys.stdout.flush()
        analysis = analyze_log_file(pod, log_file)
        connector_analyses.append(analysis)
    
    sys.stdout.write(" " * 80 + "\r")
    sys.stdout.flush()
    
    return {
        "pod": pod,
        "connectors": connector_analyses,
        "total_connectors": len(logs)
    }

def print_detailed_report(all_reports):
    """
    Print a detailed summary report of all pods and connectors
    """
    print_header("CONNECTOR TROUBLESHOOTING REPORT")
    print("Generated: " + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + "\n")
    
    total_connectors = 0
    status_counts = {
        "HEALTHY": 0, "WARNING": 0, "DEGRADED": 0, "ERROR": 0, 
        "CRITICAL": 0, "AUTH_FAILURE": 0, "CONNECTION_ERROR": 0,
        "STALE": 0, "UNKNOWN": 0, "INACCESSIBLE": 0
    }
    
    for report in all_reports:
        print_section("Pod: " + report['pod'])
        print("Total Connectors: " + str(report['total_connectors']) + "\n")
        
        if not report['connectors']:
            print(Color.YELLOW + "No connectors found" + Color.END + "\n")
            continue
        
        for connector in report['connectors']:
            total_connectors += 1
            status = connector['status']
            status_counts[status] = status_counts.get(status, 0) + 1
            
            # Color code based on status
            if status == "HEALTHY":
                status_color = Color.GREEN
            elif status in ["WARNING", "DEGRADED"]:
                status_color = Color.YELLOW
            elif status in ["ERROR", "CRITICAL", "AUTH_FAILURE", "CONNECTION_ERROR"]:
                status_color = Color.RED
            elif status == "STALE":
                status_color = Color.CYAN
            else:
                status_color = Color.END
            
            print(Color.BOLD + "Connector:" + Color.END + " " + connector['connector'])
            print("  Status: " + status_color + status + Color.END)
            print("  Errors: {0} | Warnings: {1}".format(
                connector['error_count'], connector['warning_count']))
            
            # Show specific issue counts
            if connector['auth_failures'] > 0:
                print("  " + Color.RED + "Authentication Failures: {0}".format(
                    connector['auth_failures']) + Color.END)
            if connector['connection_errors'] > 0:
                print("  " + Color.RED + "Connection Errors: {0}".format(
                    connector['connection_errors']) + Color.END)
            
            # Show HTTP error codes
            if connector['http_errors']:
                codes = ", ".join(["{0}({1}x)".format(k, v) 
                                  for k, v in sorted(connector['http_errors'].items())])
                print("  HTTP Error Codes: " + codes)
            
            # Show last activity
            if connector['last_timestamp']:
                days_ago = (datetime.now() - connector['last_timestamp']).days
                if days_ago > 0:
                    print("  Last Activity: {0} ({1} days ago)".format(
                        connector['last_timestamp'].strftime('%Y-%m-%d %H:%M'), days_ago))
                else:
                    print("  Last Activity: {0} (today)".format(
                        connector['last_timestamp'].strftime('%Y-%m-%d %H:%M')))
            
            # Show issue summary
            if connector['issue_summary']:
                print("  " + Color.RED + "Top Issues:" + Color.END)
                for issue in connector['issue_summary'][:3]:
                    print("    - " + issue)
            
            print()
    
    # Summary
    print_header("SUMMARY")
    print("Total Pods Analyzed: " + str(len(all_reports)))
    print("Total Connectors: " + str(total_connectors) + "\n")
    
    print(Color.BOLD + "Status Breakdown:" + Color.END)
    print("  " + Color.GREEN + "[OK] HEALTHY:" + Color.END + "           " + str(status_counts['HEALTHY']))
    print("  " + Color.YELLOW + "[!] WARNING:" + Color.END + "           " + str(status_counts['WARNING']))
    print("  " + Color.YELLOW + "[!] DEGRADED:" + Color.END + "          " + str(status_counts['DEGRADED']))
    print("  " + Color.RED + "[X] ERROR:" + Color.END + "             " + str(status_counts['ERROR']))
    print("  " + Color.RED + "[XX] CRITICAL:" + Color.END + "         " + str(status_counts['CRITICAL']))
    print("  " + Color.RED + "[AUTH] AUTH_FAILURE:" + Color.END + "   " + str(status_counts['AUTH_FAILURE']))
    print("  " + Color.RED + "[CONN] CONN_ERROR:" + Color.END + "     " + str(status_counts['CONNECTION_ERROR']))
    print("  " + Color.CYAN + "[STALE] STALE:" + Color.END + "         " + str(status_counts['STALE']))
    print("  [?] UNKNOWN:           " + str(status_counts['UNKNOWN']))
    print("  [X] INACCESSIBLE:      " + str(status_counts['INACCESSIBLE']))
    
    print("\n" + Color.BOLD + "Attention Required:" + Color.END)
    critical_count = (status_counts['CRITICAL'] + status_counts['ERROR'] + 
                     status_counts['AUTH_FAILURE'] + status_counts['CONNECTION_ERROR'])
    stale_count = status_counts['STALE']
    
    if critical_count > 0:
        print("  " + Color.RED + "{0} connector(s) require immediate attention".format(
            critical_count) + Color.END)
    if stale_count > 0:
        print("  " + Color.CYAN + "{0} connector(s) appear stale (no recent activity)".format(
            stale_count) + Color.END)
    if critical_count == 0 and stale_count == 0:
        print("  " + Color.GREEN + "No critical issues detected" + Color.END)

def save_report_to_file(all_reports, filename=None):
    """
    Save the report to a JSON file
    """
    if filename is None:
        filename = "connector_report_{0}.json".format(datetime.now().strftime('%Y%m%d_%H%M%S'))
    
    try:
        # Convert datetime objects to strings for JSON serialization
        for report in all_reports:
            for connector in report['connectors']:
                if connector.get('last_timestamp'):
                    connector['last_timestamp'] = connector['last_timestamp'].isoformat()
        
        with open(filename, 'w') as f:
            json.dump({
                "generated_at": datetime.now().isoformat(),
                "reports": all_reports
            }, f, indent=2)
        print("\n" + Color.GREEN + "Report saved to: " + filename + Color.END)
    except Exception as e:
        print("\n" + Color.RED + "Error saving report: " + str(e) + Color.END)

def main():
    """
    Main execution function
    """
    try:
        print_header("CONNECTOR TROUBLESHOOTING AUTOMATION")
        
        # Get all log-collector-master pods
        pods = get_log_collector_pods()
        
        if not pods:
            print("\n" + Color.RED + "No log-collector-master pods found. Exiting." + Color.END)
            sys.exit(1)
        
        # Analyze each pod
        all_reports = []
        for idx, pod in enumerate(pods, 1):
            print("\n" + Color.BOLD + "Processing pod {0}/{1}".format(idx, len(pods)) + Color.END)
            report = generate_pod_report(pod)
            all_reports.append(report)
        
        # Generate and print detailed report
        print_detailed_report(all_reports)
        
        # Ask if user wants to save report
        print("\n" + Color.BOLD + "Would you like to save this report to a file? (y/n):" + Color.END + " ", end='')
        sys.stdout.flush()
        
        # Python 2/3 compatible input
        if sys.version_info[0] >= 3:
            response = input().strip().lower()
        else:
            response = raw_input().strip().lower()
        
        if response in ['y', 'yes']:
            save_report_to_file(all_reports)
        
        print("\n" + Color.GREEN + "[OK] Troubleshooting complete!" + Color.END + "\n")
        
    except KeyboardInterrupt:
        print("\n\n" + Color.YELLOW + "Operation cancelled by user" + Color.END)
        sys.exit(0)
    except Exception as e:
        print("\n" + Color.RED + "Unexpected error: " + str(e) + Color.END)
        sys.exit(1)

if __name__ == "__main__":
    main()
