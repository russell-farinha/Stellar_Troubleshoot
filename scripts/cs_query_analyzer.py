#!/usr/bin/env python2
# -*- coding: utf-8 -*-
"""
cs_query_analyzer.py
Analyze Aella UI + Elastic logs for heavy/slow queries, correlate UI⇄Elastic,
and answer targeted questions like:
  "Who queried the most around 09:15, to which indices, and any query patterns?"

New features:
  - Time filtering: --since or --start/--end (UTC dates)
  - Timezone-aware focus window: --focus 2025-10-27T09:15 --window 15
  - Timezone inputs:
      * Preferred: --user-tz America/Denver --server-tz UTC  (uses pytz if available)
      * Fallback:  --user-utc-offset -06:00 --server-utc-offset +00:00
  - Focused activity summary (top users, endpoints, patterns)
  - Optional user zoom: --focus-user <name_or_email_fragment>
  - Summaries, correlation, and actionable findings (previous version)
"""

import os
import re
import json
import gzip
import datetime
from collections import defaultdict

LOG_DIR = "/opt/aelladata/work/aella_ui/log"

# ----------- Optional pytz support (preferred for DST correctness) -----------
try:
    import pytz
except Exception:
    pytz = None

def parse_utc_offset(s):
    """Parse a string like '+00:00', '-06:00', '+0530' into a datetime.timedelta."""
    if not s:
        return datetime.timedelta(0)
    s = s.strip()
    sign = 1
    if s[0] == '-':
        sign = -1
        s = s[1:]
    elif s[0] == '+':
        s = s[1:]
    s = s.replace(':', '')
    if len(s) == 4:
        hh = int(s[:2]); mm = int(s[2:])
    elif len(s) == 2:
        hh = int(s); mm = 0
    else:
        # Try HH:MM
        parts = s.split(':')
        if len(parts) == 2:
            hh = int(parts[0]); mm = int(parts[1])
        else:
            hh = int(s); mm = 0
    return datetime.timedelta(hours=sign*hh, minutes=sign*mm)

# ----------------------------- IO utils -----------------------------
def open_log(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "r")

def parse_ts(ts_str):
    """Parse 'YYYY-MM-DD HH:MM:SS' into naive datetime."""
    return datetime.datetime.strptime(ts_str[:19], "%Y-%m-%d %H:%M:%S")

def in_time_window(ts, start_dt, end_dt):
    """Return True if timestamp is within range (inclusive start, exclusive end)."""
    try:
        t = parse_ts(ts)
        if start_dt and t < start_dt:
            return False
        if end_dt and t >= end_dt:
            return False
        return True
    except Exception:
        return False

# ----------------------------- Parsers -----------------------------
def parse_server_logs(start_dt, end_dt):
    # Example:
    # 2025-10-27 01:00:09 [aella-ui] info [6087ms] req_id=...: GET /connect/... return 200 | metadata: {...}
    pattern = re.compile(
        r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*\[(.*?)\]\s+info\s+\[(\d+)ms\]\s+.*?\s([A-Z]+)\s+(\S+)\s+return\s+\d+\s+\|\s+metadata:\s+(.*)$"
    )
    server = []
    for fname in os.listdir(LOG_DIR):
        if "server_local" not in fname:
            continue
        fpath = os.path.join(LOG_DIR, fname)
        try:
            with open_log(fpath) as fh:
                for line in fh:
                    m = pattern.match(line)
                    if not m:
                        continue
                    ts, app, dur, method, req_path, meta = m.groups()
                    if not in_time_window(ts, start_dt, end_dt):
                        continue
                    try:
                        meta_json = json.loads(meta)
                    except Exception:
                        meta_json = {}
                    email = meta_json.get("email", "")
                    ip = meta_json.get("ip", "")
                    ua = meta_json.get("ua", "")
                    path = meta_json.get("req_path", "")

                    if email:
                        user = email
                    else:
                        # Build an informative placeholder
                        user_parts = []
                        if ip:
                            user_parts.append(ip)
                        if ua:
                            short_ua = ua.split("/")[0] if "/" in ua else ua
                            user_parts.append(short_ua)
                        if "auth" in path or "login" in path:
                            user_parts.append("login")
                        if not user_parts:
                            user = "unknown"
                        else:
                            user = " | ".join(user_parts)

                    server.append({
                        "time": ts,
                        "duration": int(dur),
                        "user": user,
                        "method": method,
                        "req_path": req_path,
                        "source": "ui",
                    })
        except Exception as e:
            print("Error reading %s: %s" % (fpath, e))
    return server

def parse_elastic_logs(start_dt, end_dt):
    # Example:
    # 2025-10-27 01:01:42 [aella_elastic] info : User <user> - Request to: <endpoint> - query body: {...}
    pattern = re.compile(
        r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*User\s+(.*?)\s+-\s+Request to:\s+(.*?)\s+-\s+query body:\s+(.*)$"
    )
    elastic = []
    for fname in os.listdir(LOG_DIR):
        if "elastic_local" not in fname:
            continue
        fpath = os.path.join(LOG_DIR, fname)
        try:
            with open_log(fpath) as fh:
                for line in fh:
                    m = pattern.match(line)
                    if not m:
                        continue
                    ts, user, endpoint, body = m.groups()
                    if not in_time_window(ts, start_dt, end_dt):
                        continue
                    # Keep raw body for pattern analysis
                    body_raw = body.strip()
                    try:
                        query = json.loads(body_raw)
                    except Exception:
                        query = {}
                    body_str = json.dumps(query) if query else body_raw

                    # Heuristic extraction
                    range_h = 0
                    for token, hours in [("now-144h", 144), ("now-120h", 120), ("now-96h", 96),
                                         ("now-72h", 72), ("now-48h", 48), ("now-30h", 30),
                                         ("now-24h", 24), ("now-12h", 12), ("now-10h", 10)]:
                        if token in body_str:
                            range_h = hours
                            break
                    size = 0
                    if isinstance(query, dict):
                        size = query.get("size", 0) or 0

                    elastic.append({
                        "time": ts,
                        "user": user,
                        "endpoint": endpoint,
                        "range_h": range_h,
                        "size": size,
                        "body": body_str
                    })
        except Exception as e:
            print("Error reading %s: %s" % (fpath, e))
    return elastic

# ----------------------------- Summaries -----------------------------
def summarize_server(server):
    total = len(server)
    slow = [s for s in server if s["duration"] > 5000]

    per_minute = defaultdict(int)
    for s in server:
        per_minute[s["time"][:16]] += 1

    per_user = defaultdict(int)
    for s in server:
        per_user[s["user"]] += 1
    top_users = sorted(per_user.items(), key=lambda x: x[1], reverse=True)[:5]

    per_path = defaultdict(int)
    for s in server:
        per_path[s["req_path"]] += 1
    top_paths = sorted(per_path.items(), key=lambda x: x[1], reverse=True)[:5]

    return {
        "total": total,
        "slow_count": len(slow),
        "slow": slow,
        "per_minute": per_minute,
        "top_users": top_users,
        "top_paths": top_paths,
    }

def summarize_elastic(elastic):
    total = len(elastic)
    large = [e for e in elastic if (e.get("size", 0) or 0) > 100]
    wide  = [e for e in elastic if (e.get("range_h", 0) or 0) > 24]
    heavy = wide + large

    per_user = defaultdict(int)
    for e in elastic:
        per_user[e["user"]] += 1
    top_users = sorted(per_user.items(), key=lambda x: x[1], reverse=True)[:5]

    per_endpoint = defaultdict(int)
    for e in elastic:
        per_endpoint[e["endpoint"]] += 1
    top_endpoints = sorted(per_endpoint.items(), key=lambda x: x[1], reverse=True)[:5]

    per_minute = defaultdict(int)
    for e in elastic:
        per_minute[e["time"][:16]] += 1

    return {
        "total": total,
        "heavy_count": len(heavy),
        "heavy": heavy,
        "large": large,
        "wide": wide,
        "per_minute": per_minute,
        "top_users": top_users,
        "top_endpoints": top_endpoints
    }

# ----------------------------- Correlation -----------------------------
def correlate(server_slow, elastic_heavy):
    """Correlate slow UI requests to heavy Elastic (±2s) with loose user match."""
    def round_to_second(ts):
        return ts[:19]

    elastic_index = defaultdict(list)
    for e in elastic_heavy:
        elastic_index[round_to_second(e["time"])].append(e)

    correlated = []
    time_window = 2
    for s in server_slow:
        try:
            base = parse_ts(s["time"])
        except Exception:
            continue
        for delta in range(-time_window, time_window + 1):
            tkey = (base + datetime.timedelta(seconds=delta)).strftime("%Y-%m-%d %H:%M:%S")
            if tkey not in elastic_index:
                continue
            for e in elastic_index[tkey]:
                su = (s.get("user") or "").split("@")[0].lower()
                eu = (e.get("user") or "").lower()
                if su and su in eu:
                    correlated.append({
                        "time": s["time"],
                        "user": e["user"],
                        "endpoint": e.get("endpoint", ""),
                        "dur_ms": s.get("duration", 0),
                        "range_h": e.get("range_h", 0),
                        "size": e.get("size", 0),
                        "source": s.get("source", "ui"),
                        "req_path": s.get("req_path", "")
                    })
    correlated.sort(key=lambda x: x["dur_ms"], reverse=True)
    return correlated

# ----------------------------- Actionable Findings -----------------------------
def analyze_bursts(per_minute_dict, top_n=1, window_minutes=5):
    if not per_minute_dict:
        return []
    minutes = sorted(per_minute_dict.keys())
    to_dt = lambda m: datetime.datetime.strptime(m + ":00", "%Y-%m-%d %H:%M:%S")
    minute_dts = [to_dt(m) for m in minutes]
    minute_to_count = {to_dt(m): per_minute_dict[m] for m in minutes}
    full = []
    if minute_dts:
        cur = minute_dts[0]
        end = minute_dts[-1]
        while cur <= end:
            full.append(cur)
            cur += datetime.timedelta(minutes=1)
    if not full:
        return []
    counts = [minute_to_count.get(t, 0) for t in full]
    ps = [0]
    for v in counts:
        ps.append(ps[-1] + v)
    best = []
    for i in range(len(full)):
        j = min(len(full)-1, i + window_minutes - 1)
        s = ps[j+1] - ps[i]
        best.append((s, full[i], full[j]))
    best.sort(key=lambda x: x[0], reverse=True)
    return best[:top_n]

def actionable_findings(server_sum, elastic_sum, correlated, analysis_hours):
    findings = []
    by_pair = defaultdict(lambda: {
        "count":0, "sum_dur":0, "max_dur":0, "sum_range":0, "sum_size":0
    })
    for c in correlated:
        key = (c["user"], c["endpoint"])
        s = by_pair[key]
        s["count"] += 1
        s["sum_dur"] += (c.get("dur_ms") or 0)
        s["max_dur"] = max(s["max_dur"], c.get("dur_ms") or 0)
        s["sum_range"] += (c.get("range_h") or 0)
        s["sum_size"]  += (c.get("size") or 0)

    def fmt_secs(ms):
        try:
            return "%.1fs" % (float(ms)/1000.0)
        except:
            return "%sms" % ms

    def rate_per_hour(cnt):
        if analysis_hours and analysis_hours > 0:
            return float(cnt)/float(analysis_hours)
        return float(cnt)

    scored = []
    for (user, endpoint), s in by_pair.items():
        cnt = s["count"]
        avg_dur = (s["sum_dur"] / max(1, cnt))
        avg_range = (s["sum_range"] / max(1, cnt))
        avg_size  = (s["sum_size"]  / max(1, cnt))
        mx_dur = s["max_dur"]
        per_hour = rate_per_hour(cnt)

        score = 0
        reasons = []
        if avg_dur > 5000:
            score += 2; reasons.append("slow (avg >5s)")
        if avg_range > 72:
            score += 2; reasons.append("wide range (avg >72h)")
        if avg_size > 10000:
            score += 2; reasons.append("large size (avg >10k)")
        if per_hour > 50:
            score += 1; reasons.append("frequent (>50/hour)")
        lu = (user or "").lower()
        if ("admin" in lu) or ("report" in lu) or ("_stellar_report_user_" in lu):
            score += 1; reasons.append("likely automation")

        scored.append({
            "score": score,
            "user": user,
            "endpoint": endpoint,
            "count": cnt,
            "per_hour": per_hour,
            "avg_dur": avg_dur,
            "max_dur": mx_dur,
            "avg_range": avg_range,
            "avg_size": avg_size,
            "reasons": reasons
        })

    scored.sort(key=lambda x: (x["score"], x["avg_dur"], x["count"]), reverse=True)
    bursts = analyze_bursts(elastic_sum.get("per_minute", {}), top_n=1, window_minutes=5)

    lines = []
    if scored:
        lines.append("=== ACTIONABLE FINDINGS ===")
        hi = [x for x in scored if x["score"] >= 3]
        med = [x for x in scored if 1 <= x["score"] < 3]

        def rec_for(x):
            recs = []
            if x["avg_range"] > 24:
                recs.append("Restrict time range to ≤24h or add rollups")
            if x["avg_size"] > 10000:
                recs.append("Cap size or page results (e.g., size ≤ 1000)")
            if x["avg_dur"] > 5000:
                recs.append("Review filters/aggregations; consider pre-aggregations")
            if x["per_hour"] > 50:
                recs.append("Reduce automation frequency, add caching")
            if not recs:
                recs.append("Review query/visualization design")
            return "; ".join(recs)

        if hi:
            lines.append("⚠️ High Impact")
            for x in hi[:10]:
                lines.append("  User: %s" % x["user"])
                lines.append("  Endpoint: %s" % x["endpoint"])
                lines.append("  Count: %d (%.1f/hour) | Avg Dur: %s (max %s) | Avg Range: %dh | Avg Size: %d"
                             % (x["count"], x["per_hour"], fmt_secs(x["avg_dur"]), fmt_secs(x["max_dur"]),
                                int(x["avg_range"]), int(x["avg_size"])))
                lines.append("  Reasons: %s" % (", ".join(x["reasons"]) or "n/a"))
                lines.append("  Recommendation: %s" % rec_for(x))
                lines.append("")
        if med:
            lines.append("ℹ️ Medium Impact")
            for x in med[:10]:
                lines.append("  User: %s | Endpoint: %s | Count: %d (%.1f/hr) | Avg Dur: %s | Range: %dh | Size: %d"
                             % (x["user"], x["endpoint"], x["count"], x["per_hour"], fmt_secs(x["avg_dur"]),
                                int(x["avg_range"]), int(x["avg_size"])))
            lines.append("")
    if bursts:
        lines.append("=== CLUSTER IMPACT PERIOD (Elastic) ===")
        total, start, end = bursts[0]
        lines.append("Window: %s to %s (5 min) | Total Elastic queries: %d"
                     % (start.strftime("%Y-%m-%d %H:%M"), end.strftime("%Y-%m-%d %H:%M"), total))
        lines.append("Action: Inspect dashboards/automation scheduled in this window (reduce frequency or cache).")
        lines.append("")

    findings_text = "\n".join(lines) if lines else "\n=== ACTIONABLE FINDINGS ===\nNo high or medium impact patterns detected in this window."
    findings.append(findings_text)
    return "\n".join(findings)

# ----------------------------- Focused Investigation -----------------------------
FOCUS_PATTERNS = ["match_all", "range", "terms", "match_phrase", "wildcard", "query_string",
                  "aggs", "aggregations", "filters", "bool", "must", "should", "must_not",
                  "script", "regexp", "prefix"]

def focused_activity(elastic_logs, start_dt, end_dt, focus_user=None):
    """Answer: who queried most in window, which indices (endpoints), and patterns in query strings."""
    subset = []
    for e in elastic_logs:
        if in_time_window(e['time'], start_dt, end_dt):
            if focus_user:
                if focus_user.lower() not in (e.get("user","").lower()):
                    continue
            subset.append(e)

    if not subset:
        print("\n=== FOCUSED ACTIVITY ===")
        print("No Elastic queries found in the focus window.")
        return

    # Counts by user and by endpoint
    per_user = defaultdict(list)
    per_endpoint = defaultdict(int)
    for e in subset:
        per_user[e['user']].append(e)
    for e in subset:
        per_endpoint[e['endpoint']] += 1

    # Pattern scan
    from collections import Counter
    pattern_counter = Counter()
    field_counter = Counter()
    for e in subset:
        body = e.get("body", "")
        # Count pattern keywords
        for pat in FOCUS_PATTERNS:
            if pat in body:
                pattern_counter[pat] += 1
        # Quick field heuristics (common ES query keys)
        for fld in ["tenantid.keyword", "timestamp", "@timestamp", "event_score",
                    "xdr_event.display_name", "xdr_event.tactic.name.keyword",
                    "event_status", "fidelity", "host.keyword", "user.keyword"]:
            if fld in body:
                field_counter[fld] += 1

    # Output
    print("\n=== FOCUSED ACTIVITY (%s to %s) ===" % (
        start_dt.strftime("%Y-%m-%d %H:%M:%S"), (end_dt - datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S")))
    print("Top users by query volume:")
    for user, q in sorted(per_user.items(), key=lambda x: len(x[1]), reverse=True)[:10]:
        uniq_eps = len(set([x['endpoint'] for x in q]))
        print("  %-30s %4d queries  | %2d endpoints" % (user, len(q), uniq_eps))

    print("\nTop endpoints (index patterns):")
    for ep, c in sorted(per_endpoint.items(), key=lambda x: x[1], reverse=True)[:20]:
        print("  %-90s %d" % (ep[:120], c))


    print("\nQuery pattern keywords (top 12):")
    for pat, c in pattern_counter.most_common(12):
        print("  %-15s %d" % (pat, c))

    print("\nFrequent fields (top 12):")
    for fld, c in field_counter.most_common(12):
        print("  %-35s %d" % (fld, c))

# ----------------------------- Printing -----------------------------
def print_header(args, start_dt, end_dt, server_sum, elastic_sum, user_focus_info=None):
    print("\n=== ANALYSIS WINDOW ===")
    print("Mode: %s" % args.mode)
    if args.since:
        print("Time window: last %dh (UTC)" % args.since)
    if args.start:
        print("Start: %s" % start_dt.strftime("%Y-%m-%d %H:%M:%S"))
    if args.end:
        print("End:   %s" % (end_dt - datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S"))
    if user_focus_info:
        print(user_focus_info)
    print("Server lines analyzed: %d (%d slow)" % (server_sum["total"], server_sum["slow_count"]))
    print("Elastic lines analyzed: %d (%d heavy)" % (elastic_sum["total"], elastic_sum["heavy_count"]))

def print_server_summary(server_sum):
    print("\n=== SERVER LOG SUMMARY ===")
    print("Total requests: %d" % server_sum["total"])
    print("Slow requests (> 5000 ms): %d" % server_sum["slow_count"])
    per_minute = server_sum["per_minute"]
    top_minutes = sorted(per_minute.items(), key=lambda x: x[1], reverse=True)[:5]
    print("Top 5 minutes by volume:")
    for t, v in top_minutes:
        print("  %-16s → %d" % (t, v))
    print("Top 5 users:")
    for u, c in server_sum["top_users"]:
        print("  %-30s %d" % (u, c))
    print("Top 5 endpoints:")
    for p, c in server_sum["top_paths"]:
        print("  %-30s %d" % (p[:30], c))

def print_elastic_summary(elastic_sum):
    print("\n=== ELASTIC LOG SUMMARY ===")
    print("Total search queries: %d" % elastic_sum["total"])
    print("Large-size queries (> 100): %d" % len(elastic_sum["large"]))
    print("Wide-range queries (> 24h): %d" % len(elastic_sum["wide"]))
    print("Top 5 elastic users:")
    for u, c in elastic_sum["top_users"]:
        print("  %-30s %d" % (u, c))
    print("Top 5 endpoints:")
    for ep, c in elastic_sum["top_endpoints"]:
        print("  %-30s %d" % (ep[:30], c))

def print_correlated(corr):
    print("\n=== CORRELATED HEAVY QUERIES ===")
    print("TIME                USER                            ENDPOINT                                                                 DURms    RANGEh   SIZE   SOURCE")
    for c in corr[:80]:
        print("%-19s %-30s %-70s %-8d %-8s %-6s %-7s" %
              (c["time"],
               c["user"][:30],
               c["endpoint"][:70],
               c["dur_ms"],
               str(c["range_h"]),
               str(c["size"]),
               c["source"]))


# ----------------------------- Time Conversion Helpers -----------------------------
def to_server_window_from_focus(focus_str, window_min, user_tz, server_tz, user_off, server_off):
    """
    Convert user-provided focus time to server-time window.
    Priority: pytz + IANA names; otherwise numeric UTC offsets.
    Returns (server_start_dt, server_end_dt, banner_text).
    """
    # Parse user focus as naive datetime
    try:
        user_naive = datetime.datetime.strptime(focus_str, "%Y-%m-%dT%H:%M")
    except Exception:
        raise SystemExit("Invalid --focus format. Use YYYY-MM-DDTHH:MM")
    half = datetime.timedelta(minutes=window_min)

    if pytz and user_tz and server_tz:
        try:
            user_zone = pytz.timezone(user_tz)
            server_zone = pytz.timezone(server_tz)
            user_dt = user_zone.localize(user_naive)
            server_dt = user_dt.astimezone(server_zone)
            start_dt = server_dt - half
            end_dt = server_dt + half
            banner = ("User time:  %s %s\nServer win: %s to %s %s"
                      % (user_dt.strftime("%Y-%m-%d %H:%M"), user_zone.zone,
                         start_dt.strftime("%Y-%m-%d %H:%M"), end_dt.strftime("%Y-%m-%d %H:%M"), server_zone.zone))
            # Drop tzinfo for internal comparisons (logs are naive server-local strings)
            return (start_dt.replace(tzinfo=None), end_dt.replace(tzinfo=None), banner)
        except Exception:
            pass  # fall through to offset method

    # Fallback: numeric UTC offsets
    u_off = parse_utc_offset(user_off or "+00:00")
    s_off = parse_utc_offset(server_off or "+00:00")
    # Convert user local naive -> UTC -> server local
    utc_dt = user_naive - u_off
    server_dt = utc_dt + s_off
    start_dt = server_dt - half
    end_dt = server_dt + half
    banner = ("User time:  %s (UTC%s)\nServer win: %s to %s (UTC%s)" %
              (user_naive.strftime("%Y-%m-%d %H:%M"), user_off or "+00:00",
               start_dt.strftime("%Y-%m-%d %H:%M"), end_dt.strftime("%Y-%m-%d %H:%M"),
               server_off or "+00:00"))
    return (start_dt, end_dt, banner)

# ----------------------------- Main -----------------------------
def main():
    import argparse
    parser = argparse.ArgumentParser(description="Analyze and correlate Aella UI + Elastic logs")
    parser.add_argument("--mode", default="summary", choices=["summary", "correlate"],
                        help="Run mode: summary or correlate")
    parser.add_argument("--since", type=int, default=None,
                        help="Only include entries newer than this many hours ago (UTC)")
    parser.add_argument("--start", type=str, default=None,
                        help="Start date YYYY-MM-DD (UTC)")
    parser.add_argument("--end", type=str, default=None,
                        help="End date YYYY-MM-DD (UTC)")
    parser.add_argument("--findings-only", action="store_true",
                        help="Print only the actionable findings section")

    # Focused investigation (timezone-aware)
    parser.add_argument("--focus", type=str, default=None,
                        help="Target timestamp (user local) in YYYY-MM-DDTHH:MM")
    parser.add_argument("--window", type=int, default=10,
                        help="Minutes on each side of --focus to include")

    # Timezone preferences (preferred)
    parser.add_argument("--user-tz", type=str, default="America/Denver",
                        help="User timezone (IANA name), requires pytz for DST correctness")
    parser.add_argument("--server-tz", type=str, default="UTC",
                        help="Server/log timezone (IANA name), requires pytz")

    # Offset fallbacks (no pytz needed)
    parser.add_argument("--user-utc-offset", type=str, default="-06:00",
                        help="User UTC offset like -06:00 (fallback if pytz unavailable)")
    parser.add_argument("--server-utc-offset", type=str, default="+00:00",
                        help="Server UTC offset like +00:00 (fallback if pytz unavailable)")

    # Optional zoom into a specific user in focus window
    parser.add_argument("--focus-user", type=str, default=None,
                        help="Filter focused analysis to a specific user (substring match)")

    args = parser.parse_args()

    # Determine main analysis window
    start_dt = None
    end_dt = None
    analysis_hours = None
    now = datetime.datetime.utcnow()

    user_focus_info = None

    # Focus window (overrides start/end/since)
    if args.focus:
        start_dt, end_dt, banner = to_server_window_from_focus(
            args.focus, args.window, args.user_tz, args.server_tz,
            args.user_utc_offset, args.server_utc_offset
        )
        user_focus_info = banner
    else:
        if args.since:
            start_dt = now - datetime.timedelta(hours=args.since)
            end_dt = now
        if args.start:
            try:
                start_dt = datetime.datetime.strptime(args.start, "%Y-%m-%d")
            except Exception:
                pass
        if args.end:
            try:
                end_dt = datetime.datetime.strptime(args.end, "%Y-%m-%d") + datetime.timedelta(days=1)
            except Exception:
                pass

    if start_dt and end_dt:
        delta = end_dt - start_dt
        analysis_hours = max(0.0, delta.total_seconds() / 3600.0)
    elif args.since:
        analysis_hours = float(args.since)

    # Parse logs within window
    server = parse_server_logs(start_dt, end_dt)
    elastic = parse_elastic_logs(start_dt, end_dt)

    # Summaries
    server_sum = summarize_server(server)
    elastic_sum = summarize_elastic(elastic)

    # Header
    print_header(args, start_dt, end_dt, server_sum, elastic_sum, user_focus_info)

    # Optional focused investigation (answers your 9:15 question)
    if args.focus:
        focused_activity(elastic, start_dt, end_dt, focus_user=args.focus_user)

    # Correlation & findings
    corr = []
    if args.mode == "correlate":
        corr = correlate(server_sum["slow"], elastic_sum["heavy"])
        if not args.findings_only:
            print_server_summary(server_sum)
            print_elastic_summary(elastic_sum)
            print_correlated(corr)

    # Actionable findings
    print("")
    print(actionable_findings(server_sum, elastic_sum, corr, analysis_hours))

if __name__ == "__main__":
    main()
