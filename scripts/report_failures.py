#!/usr/bin/env python2
import argparse
import gzip
import os
import re
import sys
import json
from collections import defaultdict

GENERATOR_LOG_DIR = "/opt/aelladata/work/stellar_report/log"
MAIL_LOG_DIR = "/opt/aelladata/work/stellar_mail/log"

def parse_generator_line(line):
    m = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[stellar-report\] (error|info):.*?\(name: ([^,]+),.*\): (.*)$", line)
    if m:
        ts, _, report, error = m.groups()
        return {"ts": ts, "report": report.strip(), "error": error.strip(), "stage": "GENERATOR"}
    return None

def parse_mail_line(line):
    m = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[stellar-mailstation\] .*?: (Message failed.*|.*entity too large.*)$", line)
    if m:
        ts, error = m.groups()
        return {"ts": ts, "report": "Unknown", "error": error.strip(), "stage": "MAIL"}
    return None

def scan_logs(directory, parser):
    failures = []
    if not os.path.exists(directory):
        return failures
    for fn in sorted(os.listdir(directory)):
        if not fn.endswith(".gz"):
            continue
        path = os.path.join(directory, fn)
        try:
            with gzip.open(path, "rt") as f:
                for line in f:
                    rec = parser(line)
                    if rec:
                        failures.append(rec)
        except Exception:
            continue
    return failures

def correlate(generator_failures, mail_failures):
    gen_index = defaultdict(list)
    for g in generator_failures:
        key = g["ts"][:16]  # minute resolution
        gen_index[key].append(g)

    for m in mail_failures:
        key = m["ts"][:16]
        if key in gen_index:
            m["report"] = gen_index[key][0]["report"]
            m["correlated"] = True
    return mail_failures

def deduplicate_failures(failures):
    seen = set()
    unique = []
    for f in failures:
        sig = (f["stage"], f["ts"], f["report"], f["error"])
        if sig not in seen:
            seen.add(sig)
            unique.append(f)
    return unique

def group_by_report(failures):
    grouped = defaultdict(list)
    for f in failures:
        grouped[f["report"]].append(f)
    return grouped

def output_console_grouped(grouped_failures):
    print("=== Consolidated Report Failures (Grouped by Report) ===\n")
    for report in sorted(grouped_failures.keys()):
        print("### {}".format(report))
        for f in sorted(grouped_failures[report], key=lambda x: x["ts"]):
            corr = " (correlated)" if f.get("correlated") else ""
            try:
                print("{stage:<10} | {ts} | {error}{corr}".format(
                    stage=f["stage"], ts=f["ts"], error=f["error"], corr=corr
                ))
            except IOError:
                sys.exit(0)  # Handle broken pipe
        print("")

def output_console_chronological(failures):
    print("=== Consolidated Report Failures (Chronological) ===\n")
    for f in sorted(failures, key=lambda x: x["ts"]):
        corr = " (correlated)" if f.get("correlated") else ""
        try:
            print("{stage:<10} | {ts} | {report} | {error}{corr}".format(
                stage=f["stage"], ts=f["ts"], report=f["report"], error=f["error"], corr=corr
            ))
        except IOError:
            sys.exit(0)

def output_json_grouped(grouped_failures):
    print(json.dumps(grouped_failures, indent=2))

def output_json_chronological(failures):
    print(json.dumps(sorted(failures, key=lambda x: x["ts"]), indent=2))

def main():
    parser = argparse.ArgumentParser(description="Analyze report/mail failures")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--chronological", action="store_true", help="Show output in chronological order instead of grouped by report")
    args = parser.parse_args()

    generator_failures = scan_logs(GENERATOR_LOG_DIR, parse_generator_line)
    mail_failures = scan_logs(MAIL_LOG_DIR, parse_mail_line)
    mail_failures = correlate(generator_failures, mail_failures)

    all_failures = generator_failures + mail_failures
    all_failures = deduplicate_failures(all_failures)

    if args.chronological:
        if args.json:
            output_json_chronological(all_failures)
        else:
            output_console_chronological(all_failures)
    else:
        grouped = group_by_report(all_failures)
        if args.json:
            output_json_grouped(grouped)
        else:
            output_console_grouped(grouped)

if __name__ == "__main__":
    main()
