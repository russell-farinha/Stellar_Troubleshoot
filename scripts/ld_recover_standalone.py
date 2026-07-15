#!/usr/bin/env python2
"""
Standalone LaunchDarkly (LD) fleet status scan + recovery -- ON-PREM,
Python 2 AND Python 3 compatible, zero repo deps.

INTERPRETER: runs under python2 or python3 -- use whichever the box has.
When launched through the Orion troubleshooter menu, the launcher picks
python3 if available (falling back to `python`), so python3 compatibility
is required there. When copied to a box directly, invoke explicitly
(`python2 ld_recover_standalone.py ...` or `python3 ...`).

DISTRIBUTION MODEL: either launch via the Orion troubleshooter menu, or copy
this single file directly onto a customer's on-prem k8s master and run it
there with the box's own interpreter. Run the same file on each master that
needs it (DL, DA, ...); it always just inspects/acts on whatever k8s
deployments/statefulsets are running locally. Stdlib only (json, re,
subprocess, argparse, csv) -- no imports from this repo.
Matching/classification logic is duplicated here from
scripts/common/utils/ld_log_scan.py -- keep the two in sync by hand.

MUTATION GATE (matches this repo's `resolve_mutation_gate()` convention,
scripts/ngsaas/k8s/m.py): this script ALWAYS defaults to REPORT-ONLY, no
flag needed to get that -- restarting anything requires an explicit
--confirm (or --yes) flag. A plain run with no flags only ever reports.
Standard workflow: run with no flags first, review what it would restart,
then re-run with --confirm once approved.

RECOVERY LOGIC (learned live during the 2026-07-10 LD platform outage and
subsequent stag-511 fault-injection testing), only under --confirm:
1. Check ld-relay /status first. If ld-relay itself is unhealthy
   (connection != VALID), restarting downstream services is pointless --
   they will keep failing to init no matter how many times they're
   restarted, because they depend on this relay locally. Fix the relay
   FIRST -- wait for its rollout AND for its own /status to actually go
   healthy (confirmed live: a bad config can leave the pod Running/Ready
   forever while connectionStatus stays stuck INITIALIZING -- a completed
   `kubectl rollout status` alone does NOT mean ld-relay recovered). If it
   never reaches healthy within RELAY_RECOVERY_TIMEOUT_SECONDS, this script
   aborts entirely rather than restarting anything downstream for nothing.
   Also checks Service-level reachability, not just the pod's own local
   /status (confirmed live: a broken Service selector/Endpoints leaves the
   pod reporting itself healthy while every real client gets connection
   refused) -- if the relay process is healthy but unreachable via its
   Service, this is a routing problem, not a process problem, so restarting
   ld-relay is skipped entirely (it would not help).
2. Only after ld-relay is confirmed healthy (or was already healthy), restart
   services whose recent logs match a known restart-fixable pattern
   (RESTART_CANDIDATE_PATTERNS below) -- this excludes patterns confirmed
   NOT to be fixed by a restart (e.g. a flag with no configured default,
   or an unknown/nonexistent flag key -- those are code/config bugs, not
   stuck clients).
3. Validate: wait for each restart to roll out, then re-check its logs and
   report whether the issue actually cleared.

Examples:
    # report only, never mutates -- checks the last 60 minutes by default
    python2 ld_recover_standalone.py

    # check a specific known incident window instead
    python2 ld_recover_standalone.py --since "2026-07-10 22:12:08"

    # actually restart ld-relay (if unhealthy) then every confirmed
    # restart-candidate service, then validate each one cleared
    python2 ld_recover_standalone.py --since "2026-07-10 22:12:08" --confirm

    # show every scanned service, not just the ones with issues (default
    # only prints issues)
    python2 ld_recover_standalone.py --verbose
"""
from __future__ import print_function

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta


def _default_kubectl_prefix():
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        return "KUBECONFIG=/admin.conf kubectl"
    return "sudo -E KUBECONFIG=/admin.conf kubectl"


DEFAULT_KUBECTL_PREFIX = _default_kubectl_prefix()

# ---------------------------------------------------------------------------
# Matching/classification constants -- ported verbatim from
# scripts/common/utils/ld_log_scan.py. Kept in sync by hand (see module
# docstring); if that file's constants change, update these too.
# ---------------------------------------------------------------------------

FF_SOURCE_PREFIX = "common-config-ff"

LD_LOG_KEYWORDS = (
    "launchdarkly",
    "ld-relay",
    "fflag",
    "feature flag",
    "feature store",
    "sdk key",
)

KNOWN_LD_ERROR_PHRASES = (
    "invalid sdk key",
    "unauthorized",
    "connection pool is full",
    "context deadline exceeded",
    "unexpected error while sending events",
    "feature store unavailable",
    "sdk client not initialized",
    "before client has initialized",
    # Java SDK phrases this differently ("Evaluation called before client
    # initialized" -- no "has") -- confirmed missed entirely without this,
    # e.g. slowpath-tm's com.launchdarkly.sdk.server.LDClient.Evaluation logs.
    "before client initialized",
)

BENIGN_LD_PHRASES = (
    "feature flags initialized",
    "feature flag initialized",
    "connected to launchdarkly",
    # LD's event API (analytics + diagnostic events, /bulk and /diagnostic)
    # is fire-and-forget telemetry -- a failure here means some usage/debug
    # data got dropped, NOT that flag evaluation is broken (that's the
    # streaming connection, matched separately above). Confirmed live on
    # stag-511: every ld-relay restart, even a routine/healthy one, produces
    # a burst of these fleet-wide as clients briefly can't flush their event
    # queue -- pure noise for an "is anything actually broken" report.
    "error posting",
    # Node SDK's own auto-reconnect message for a transient streaming
    # hiccup -- excluded per user judgment call (2026-07-11), same tradeoff
    # noted in scripts/common/utils/ld_log_scan.py: unlike "error posting",
    # streaming IS how flags actually get delivered, so this also hides a
    # Node client stuck reconnecting for a long time, not just a blip.
    "streaming request - will retry",
    # kubernetes.client.rest's own DEBUG dump of an API response body --
    # can contain "ld-relay" purely because a pod named ld-relay-* exists
    # in the namespace, not because anything is actually LD-related. See
    # scripts/common/utils/ld_log_scan.py for the full note.
    "kubernetes.client.rest",
    # Node SDK's stuck-at-init messages. Initially added as a
    # restart-candidate pattern (a genuinely missed phrasing variant) but
    # confirmed live on stag-511 this SPECIFIC Node client self-heals via
    # its own retry loop the moment ld-relay becomes reachable again -- no
    # restart needed, same mechanism as "streaming request - will retry".
    "before launchdarkly client initialization",
    "not initialized yet",
    "initialization timeout",
)

# Patterns confirmed (2026-07-10 incident) to be resolved by restarting the
# affected pod -- excludes patterns confirmed NOT restart-fixable (a flag
# with no default configured, or an unknown flag key -- both code/config
# bugs unrelated to a stuck client).
RESTART_CANDIDATE_PATTERNS = (
    "feature store unavailable",
    "stale",
    "before client has initialized",
    "before client initialized",  # Java SDK variant, no "has" -- see KNOWN_LD_ERROR_PHRASES
    "sdk timeout",
    "interrupted",
)

LOG_TAIL_LINES = 200
MAX_MATCHED_LINES_PER_SERVICE = 5

# "still_live" requires the latest matched line within this many seconds of
# scan time -- NOT just "after `since`" (since is usually just the scan
# window's own start, e.g. "5 minutes ago", so almost any match in the
# window trivially satisfies "> since" even if the error actually stopped
# well before the scan ran). Keep in sync with the same constant in
# scripts/common/utils/ld_log_scan.py.
STILL_LIVE_FRESHNESS_SECONDS = 120

# How long to keep polling ld-relay's own /status after restarting it before
# giving up. A completed `kubectl rollout status` only proves the pod passed
# its readiness probe, not that it actually reconnected to LaunchDarkly (a
# bad config leaves it Running/Ready forever while still INITIALIZING) --
# this timeout governs the *real* health poll, not just the rollout.
RELAY_RECOVERY_TIMEOUT_SECONDS = 180
RELAY_RECOVERY_POLL_SECONDS = 10

_LOG_LEVEL_MARKER_RE = re.compile(
    r'\b(ERROR|WARN(?:ING)?)\b|"level"\s*:\s*"(error|warn(?:ing)?)"', re.IGNORECASE
)
_TS_ISO_RE = re.compile(r'(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})')
_TS_EPOCH_RE = re.compile(r'"ts"\s*:\s*(\d+\.?\d*)')

CSV_FIELDNAMES = (
    "service", "namespace", "kind", "ready_replicas", "replicas",
    "matched", "restart_candidate", "still_live", "latest_match_ts", "action",
)


# ---------------------------------------------------------------------------
# kubectl invocation
# ---------------------------------------------------------------------------

def run_kubectl(kubectl_prefix, args):
    cmd = kubectl_prefix.split() + list(args)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate()
    # Python 3 returns bytes here; downstream regex/log matching needs str.
    # Python 2 (bytes is str) is left untouched.
    if not isinstance(stdout, str):
        stdout = stdout.decode("utf-8", "replace")
    if not isinstance(stderr, str):
        stderr = stderr.decode("utf-8", "replace")
    return proc.returncode, stdout, stderr


def kubectl_json(kubectl_prefix, args):
    rc, stdout, stderr = run_kubectl(kubectl_prefix, args)
    if rc != 0:
        return None, stderr.strip()
    try:
        return json.loads(stdout), None
    except ValueError as e:
        return None, "could not parse kubectl JSON output: %s" % e


# ---------------------------------------------------------------------------
# Log-error classification (ported from ld_log_scan.py)
# ---------------------------------------------------------------------------

def extract_log_timestamp(line):
    m = _TS_ISO_RE.search(line)
    if m:
        return "%s %s" % (m.group(1), m.group(2))
    m = _TS_EPOCH_RE.search(line)
    if m:
        dt = datetime(1970, 1, 1) + timedelta(seconds=float(m.group(1)))
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    return None


def is_ld_error_line(line):
    lower = line.lower()
    if not any(k in lower for k in LD_LOG_KEYWORDS):
        return False
    if any(p in lower for p in BENIGN_LD_PHRASES):
        return False
    if any(p in lower for p in KNOWN_LD_ERROR_PHRASES):
        return True

    stripped = line.strip()
    if stripped.startswith("{"):
        try:
            obj = json.loads(stripped)
        except ValueError:
            obj = None
        if isinstance(obj, dict):
            level = str(obj.get("level") or obj.get("levelname") or "").lower()
            return level in ("error", "warn", "warning")

    return bool(_LOG_LEVEL_MARKER_RE.search(line[:40]))


def classify_log_text(log_text, since=None):
    lines = log_text.splitlines()
    matched = [line for line in lines if is_ld_error_line(line)]
    matched = matched[-MAX_MATCHED_LINES_PER_SERVICE:]
    restart_candidate = any(
        pat in line.lower() for line in matched for pat in RESTART_CANDIDATE_PATTERNS
    )
    result = {
        "ok": True,
        "matched_lines": matched,
        "restart_candidate": restart_candidate,
    }
    if since is not None:
        timestamps = [t for t in (extract_log_timestamp(l) for l in matched) if t]
        latest = max(timestamps) if timestamps else None
        result["latest_match_ts"] = latest
        if latest is None:
            result["still_live"] = None
        else:
            freshness_cutoff = (datetime.utcnow() - timedelta(seconds=STILL_LIVE_FRESHNESS_SECONDS)).strftime("%Y-%m-%d %H:%M:%S")
            result["still_live"] = latest > since and latest >= freshness_cutoff
    return result


def merge_classify_results(results):
    """Merge one classify_log_text() result per pod of a multi-replica
    service into a single aggregate -- a service is flagged if ANY of its
    pods show the issue."""
    ok_results = [r for r in results if r.get("ok")]
    if not ok_results:
        errors = "; ".join(r.get("error", "unknown") for r in results if not r.get("ok"))
        return {"ok": False, "error": errors or "no pods checked"}

    matched = []
    for r in ok_results:
        matched.extend(r.get("matched_lines", []))
    matched = matched[-MAX_MATCHED_LINES_PER_SERVICE:]
    restart_candidate = any(r.get("restart_candidate") for r in ok_results)
    merged = {"ok": True, "matched_lines": matched, "restart_candidate": restart_candidate}

    if any("still_live" in r for r in ok_results):
        timestamps = [r.get("latest_match_ts") for r in ok_results if r.get("latest_match_ts")]
        merged["latest_match_ts"] = max(timestamps) if timestamps else None
        still_live_values = [r.get("still_live") for r in ok_results if "still_live" in r]
        if any(v is True for v in still_live_values):
            merged["still_live"] = True
        elif all(v is False for v in still_live_values):
            merged["still_live"] = False
        else:
            merged["still_live"] = None
    return merged


def find_ff_consuming_workloads(workloads_json, kind):
    """Given a `kubectl get <deployments|statefulsets> -o json` payload,
    return workloads whose containers reference a common-config-ff*
    secret/configmap -- i.e. participate in LD. Each result includes its
    namespace, `kind` ("Deployment"/"StatefulSet"), and label `selector` so
    callers can resolve every pod it owns (kubectl logs deploy/X /
    statefulset/X silently reads only ONE pod with >1 replica -- confirmed
    live on stag-511's 3-replica `slowpath-tm` StatefulSet)."""
    services = []
    for dep in workloads_json.get("items", []):
        meta = dep.get("metadata", {})
        name = meta.get("name", "unknown")
        namespace = meta.get("namespace", "default")
        containers = dep.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
        consumes_ff = False
        for c in containers:
            for ef in c.get("envFrom", []):
                ref = ef.get("secretRef", {}).get("name") or ef.get("configMapRef", {}).get("name")
                if ref and ref.startswith(FF_SOURCE_PREFIX):
                    consumes_ff = True
                    break
            if not consumes_ff:
                for e in c.get("env", []):
                    value_from = e.get("valueFrom", {})
                    ref = (
                        value_from.get("secretKeyRef", {}).get("name")
                        or value_from.get("configMapKeyRef", {}).get("name")
                    )
                    if ref and ref.startswith(FF_SOURCE_PREFIX):
                        consumes_ff = True
                        break
            if consumes_ff:
                break
        if not consumes_ff:
            continue

        status = dep.get("status", {})
        match_labels = dep.get("spec", {}).get("selector", {}).get("matchLabels", {}) or {}
        services.append({
            "name": name,
            "namespace": namespace,
            "kind": kind,
            "ready_replicas": status.get("readyReplicas", 0) or 0,
            "replicas": status.get("replicas", 0) or 0,
            "selector": match_labels,
        })
    return services


def find_ff_consuming_services(deployments_json, statefulsets_json=None):
    services = find_ff_consuming_workloads(deployments_json, "Deployment")
    if statefulsets_json is not None:
        services += find_ff_consuming_workloads(statefulsets_json, "StatefulSet")
    return services


def build_label_selector(match_labels):
    return ",".join("%s=%s" % (k, v) for k, v in match_labels.items())


def pod_names_for_service(svc):
    """Deterministic pod names for a StatefulSet (<name>-0 .. <name>-(replicas-1)
    -- ordinals are guaranteed stable, no extra kubectl call needed). Returns
    None for a Deployment (random pod-name suffix -- must resolve via label
    selector instead)."""
    if svc.get("kind") != "StatefulSet":
        return None
    replicas = svc.get("replicas", 0) or 0
    if replicas <= 0:
        return None
    return ["%s-%d" % (svc["name"], i) for i in range(replicas)]


def resolve_pod_names(kubectl_prefix, svc):
    deterministic = pod_names_for_service(svc)
    if deterministic is not None:
        return deterministic
    selector = build_label_selector(svc.get("selector") or {})
    if not selector:
        return [svc["name"]]
    rc, stdout, stderr = run_kubectl(
        kubectl_prefix,
        ["get", "pods", "-n", svc["namespace"], "-l", selector, "-o", "jsonpath={.items[*].metadata.name}"],
    )
    if rc != 0 or not stdout.strip():
        return [svc["name"]]
    return stdout.split()


def check_service_log_errors(kubectl_prefix, svc, since, log_since_time):
    """Check every pod backing a service for LD-related log errors (current
    + --previous container instance), merged across replicas. Shared by the
    initial scan and the post-restart validation pass so both use identical
    logic."""
    pod_names = resolve_pod_names(kubectl_prefix, svc)
    per_pod_results = []
    for pod_name in pod_names:
        base_cmd = [
            "logs", "pod/%s" % pod_name, "-n", svc["namespace"],
            "--all-containers=true", "--tail", str(LOG_TAIL_LINES), "--since-time", log_since_time,
        ]
        rc, stdout, stderr = run_kubectl(kubectl_prefix, base_cmd)
        if rc != 0:
            per_pod_results.append({"ok": False, "error": stderr.strip()[:200]})
        else:
            per_pod_results.append(classify_log_text(stdout, since=since))
        # PREVIOUS container instance -- a crash-looping pod's current
        # container may have just restarted with fresh/empty logs, hiding
        # the actual crash reason from the last failed attempt.
        prev_rc, prev_stdout, _ = run_kubectl(kubectl_prefix, base_cmd + ["--previous"])
        if prev_rc == 0 and prev_stdout.strip():
            per_pod_results.append(classify_log_text(prev_stdout, since=since))
    return merge_classify_results(per_pod_results)


# ---------------------------------------------------------------------------
# ld-relay status
# ---------------------------------------------------------------------------

def find_ld_relay_namespaces(deployments_json):
    """Find every namespace running a deployment literally named 'ld-relay'
    -- don't assume it lives in 'default'. Usually returns one namespace, but
    loop-friendly in case a box runs more than one."""
    namespaces = []
    for dep in deployments_json.get("items", []):
        meta = dep.get("metadata", {})
        if meta.get("name") == "ld-relay":
            namespaces.append(meta.get("namespace", "default"))
    return namespaces


def check_ld_relay_status(kubectl_prefix, namespace):
    rc, stdout, stderr = run_kubectl(
        kubectl_prefix,
        ["exec", "deploy/ld-relay", "-n", namespace, "--",
         "wget", "-qO-", "http://localhost:8030/status"],
    )
    if rc != 0:
        return {"ok": False, "error": stderr.strip()[:300] or "could not exec into ld-relay"}
    try:
        status = json.loads(stdout)
    except ValueError:
        return {"ok": False, "error": "could not parse ld-relay status JSON: %s" % stdout[:200]}

    environments = status.get("environments", {})
    all_valid = True
    env_summaries = []
    for env_key, env_data in environments.items():
        conn = env_data.get("connectionStatus", {})
        store = env_data.get("dataStoreStatus", {})
        conn_state = conn.get("state", "unknown")
        if conn_state != "VALID":
            all_valid = False
        env_summaries.append({
            "env": (env_key[:16] + "...") if len(env_key) > 16 else env_key,
            "connection_state": conn_state,
            "store_state": store.get("state", "unknown"),
        })
    result = {"ok": True, "healthy": all_valid, "environments": env_summaries}

    # The check above execs INTO the ld-relay pod and hits its own
    # localhost:8030 -- a loopback call that bypasses the Service entirely.
    # A relay that's up and LD-connected can still be completely unreachable
    # by every downstream consumer if the Service/Endpoints are broken (e.g.
    # a bad selector) -- confirmed live on stag-511: patching the Service
    # selector to a non-matching value left this check reporting HEALTHY
    # while every real client got connection refused. Only worth probing
    # Service routing once the pod itself already looks healthy locally.
    if all_valid:
        svc_rc, _, svc_stderr = run_kubectl(
            kubectl_prefix,
            ["exec", "deploy/ld-relay", "-n", namespace, "--",
             "wget", "-qO-", "--timeout=5",
             "http://ld-relay.%s.svc.cluster.local:8030/status" % namespace],
        )
        result["service_reachable"] = (svc_rc == 0)
        if svc_rc != 0:
            result["service_error"] = svc_stderr.strip()[:200]
    return result


# ---------------------------------------------------------------------------
# Restart action (mutation-gated)
# ---------------------------------------------------------------------------

def restart_deployment(kubectl_prefix, namespace, name, confirm, kind="Deployment"):
    """Returns (action_str, ok). action_str is one of: 'would-restart
    (pass --confirm to act)', 'restarted', 'restart-failed'.

    Restarts the WORKLOAD (not a specific pod) -- kubectl's own rollout
    restart already cycles every replica behind it, so this is unaffected by
    the "kubectl logs only reads one pod" gap that required per-pod checking
    on the scan side (see resolve_pod_names / match_pods_to_selector).
    """
    if not confirm:
        return "would-restart (pass --confirm to act)", True

    resource_prefix = "deploy" if kind == "Deployment" else "statefulset"
    rc, stdout, stderr = run_kubectl(
        kubectl_prefix, ["rollout", "restart", "%s/%s" % (resource_prefix, name), "-n", namespace]
    )
    if rc != 0:
        return "restart-failed: %s" % stderr.strip()[:200], False
    return "restarted", True


def wait_for_rollout(kubectl_prefix, namespace, name, timeout_seconds=90, kind="Deployment"):
    resource_prefix = "deploy" if kind == "Deployment" else "statefulset"
    rc, stdout, stderr = run_kubectl(
        kubectl_prefix,
        ["rollout", "status", "%s/%s" % (resource_prefix, name), "-n", namespace,
         "--timeout=%ds" % timeout_seconds],
    )
    return rc == 0


def wait_for_relay_healthy(kubectl_prefix, namespace, timeout_seconds=RELAY_RECOVERY_TIMEOUT_SECONDS,
                            poll_seconds=RELAY_RECOVERY_POLL_SECONDS):
    """Poll check_ld_relay_status() until it reports healthy, or give up after
    timeout_seconds. A completed kubectl rollout only means the pod passed its
    readiness probe -- it says nothing about whether ld-relay actually
    reconnected to LaunchDarkly. Confirmed live: a bad streamUri leaves the
    pod Running/Ready forever while connectionStatus stays stuck at
    INITIALIZING -- kubectl rollout status alone would have reported success
    and let the script proceed to restart every downstream service for
    nothing. Returns (recovered: bool, last_relay_result: dict|None)."""
    deadline = time.time() + timeout_seconds
    last_relay = None
    while True:
        last_relay = check_ld_relay_status(kubectl_prefix, namespace)
        if last_relay.get("ok") and last_relay.get("healthy"):
            return True, last_relay
        if time.time() >= deadline:
            return False, last_relay
        time.sleep(poll_seconds)


# ---------------------------------------------------------------------------
# Report / CSV output
# ---------------------------------------------------------------------------

def print_relay_result(relay):
    if not relay.get("ok"):
        print("ld-relay: FAILED -- %s" % relay.get("error"))
        return
    healthy = "HEALTHY" if relay.get("healthy") else "UNHEALTHY"
    print("ld-relay: %s" % healthy)
    for env in relay.get("environments", []):
        print("  [%s]: connection=%s store=%s" % (
            env["env"], env["connection_state"], env["store_state"]
        ))
    if relay.get("healthy") and relay.get("service_reachable") is False:
        print("  WARNING: relay process is healthy locally, but UNREACHABLE via its "
              "own Service (%s) -- every downstream client will fail to connect. "
              "Restarting ld-relay will NOT fix this -- check the Service "
              "selector/Endpoints instead." % (relay.get("service_error") or "no response"))


def print_services_result(services, verbose=False):
    # Summary line FIRST -- with up to ~60 services printed below, the 1-2
    # that actually matter can get buried; lead with the headline number.
    # Default behavior only lists services WITH an issue -- pass --verbose
    # to also list the healthy ones.
    with_issues = [s for s in services if (s.get("log_errors") or {}).get("matched_lines")]
    still_live_n = sum(1 for s in with_issues if (s.get("log_errors") or {}).get("still_live") is True)
    restart_eligible_n = sum(1 for s in with_issues if (s.get("log_errors") or {}).get("restart_candidate"))
    print("\nScanned %d services -- %d with issues (%d STILL LIVE, %d restart-eligible)" % (
        len(services), len(with_issues), still_live_n, restart_eligible_n
    ))
    if not with_issues and not verbose:
        print("(all clean -- pass --verbose to list every service checked)")
        return

    for svc in services:
        log_errors = svc.get("log_errors")
        has_issue = bool(log_errors and log_errors.get("matched_lines"))
        if not verbose and not has_issue:
            continue
        healthy = svc["replicas"] > 0 and svc["ready_replicas"] == svc["replicas"]
        status = "OK" if healthy else "UNHEALTHY"
        kind_tag = "" if svc.get("kind", "Deployment") == "Deployment" else " (%s)" % svc["kind"]
        print("  [%s] %s/%s%s: %s/%s ready" % (
            status, svc["namespace"], svc["name"], kind_tag, svc["ready_replicas"], svc["replicas"]
        ))
        if log_errors is not None:
            if not log_errors.get("ok"):
                print("      log check failed: %s" % log_errors.get("error"))
            elif log_errors.get("matched_lines"):
                tag = " (restart candidate)" if log_errors.get("restart_candidate") else ""
                still_live = log_errors.get("still_live")
                if still_live is True:
                    tag += " (STILL LIVE, last seen %s)" % log_errors.get("latest_match_ts")
                elif still_live is False:
                    tag += " (stale, last seen %s)" % log_errors.get("latest_match_ts")
                print("      LD errors in logs%s:" % tag)
                for line in log_errors["matched_lines"]:
                    print("        %s" % line.strip()[:200])
        if "action" in svc:
            print("      action: %s" % svc["action"])


def write_csv(services, path):
    # csv module wants binary mode on Python 2, text mode (no newline
    # translation) on Python 3.
    if sys.version_info[0] >= 3:
        f = open(path, "w", newline="")
    else:
        f = open(path, "wb")
    try:
        writer = csv.DictWriter(f, fieldnames=list(CSV_FIELDNAMES))
        writer.writeheader()
        for svc in services:
            log_errors = svc.get("log_errors") or {}
            writer.writerow({
                "service": svc.get("name", ""),
                "namespace": svc.get("namespace", ""),
                "kind": svc.get("kind", "Deployment"),
                "ready_replicas": svc.get("ready_replicas", ""),
                "replicas": svc.get("replicas", ""),
                "matched": bool(log_errors.get("matched_lines")),
                "restart_candidate": log_errors.get("restart_candidate", ""),
                "still_live": log_errors.get("still_live", ""),
                "latest_match_ts": log_errors.get("latest_match_ts", ""),
                "action": svc.get("action", ""),
            })
    finally:
        f.close()


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Standalone on-prem LD fleet status scan + recovery (Python 2/3, no repo deps). "
                     "Run directly on this k8s master. Always checks the last --recent-minutes of "
                     "logs and reports report-only by default; restarting anything requires "
                     "--confirm.",
        epilog=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--recent-minutes", type=int, default=60,
                         help="Check logs from the last N minutes (default: 60) -- both the "
                              "server-side kubectl fetch and the STILL LIVE classification cutoff. "
                              "No manual timestamp math needed for the common case of 'what's wrong "
                              "right now'.")
    parser.add_argument("--since", default=None,
                         help="Override --recent-minutes with a specific UTC cutoff "
                              "'YYYY-MM-DD HH:MM:SS' instead (e.g. a known incident start time).")
    parser.add_argument("--verbose", action="store_true",
                         help="Also list every healthy/clean service checked. By default only "
                              "services with an issue are printed -- the common case is a fast "
                              "glance at what's wrong, not a full inventory.")
    parser.add_argument("--kubectl-prefix", default=DEFAULT_KUBECTL_PREFIX,
                         help="Command prefix used to invoke kubectl on this box "
                              "(default: %r)" % DEFAULT_KUBECTL_PREFIX)
    parser.add_argument("--confirm", "--yes", dest="confirm", action="store_true",
                         help="Actually restart every STILL LIVE + restart-candidate service found "
                              "(and ld-relay first, if it's unhealthy). Without this flag, nothing "
                              "is ever mutated -- the report always shows what WOULD be restarted.")
    parser.add_argument("--csv-out", default=None,
                         help="Also write one row per LD-consuming service to this CSV path")
    args = parser.parse_args()

    if args.since:
        since_str = args.since
        cutoff_dt = datetime.strptime(since_str, "%Y-%m-%d %H:%M:%S")
    else:
        cutoff_dt = datetime.utcnow() - timedelta(minutes=args.recent_minutes)
        since_str = cutoff_dt.strftime("%Y-%m-%d %H:%M:%S")
        print("(checking logs since %s, last %d min -- pass --since for a specific window)\n" % (
            since_str, args.recent_minutes
        ))
    args.since = since_str
    log_since_time = cutoff_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Preflight: fail fast with a clear message if kubectl itself isn't
    # reachable, instead of a confusing error deep in the first real call.
    rc, _, stderr = run_kubectl(args.kubectl_prefix, ["version", "--client"])
    if rc != 0:
        print("ERROR: kubectl not usable with prefix %r -- %s" % (args.kubectl_prefix, stderr.strip()[:200]))
        print("(check --kubectl-prefix, or that this box actually has kubectl/admin.conf)")
        sys.exit(1)

    # Fetch every deployment once, across ALL namespaces -- both the ld-relay
    # lookup and the FF-consuming service scan read from this same JSON, so
    # ld-relay is found wherever it actually lives instead of assuming
    # 'default', and nothing outside 'default' is silently skipped.
    deployments_json, err = kubectl_json(
        args.kubectl_prefix, ["get", "deployments", "-A", "-o", "json"]
    )
    if deployments_json is None:
        print("ERROR: kubectl get deployments failed -- %s" % err)
        sys.exit(1)
    statefulsets_json, _ = kubectl_json(args.kubectl_prefix, ["get", "statefulsets", "-A", "-o", "json"])
    if statefulsets_json is None:
        statefulsets_json = {"items": []}

    # Relay check always runs -- if this box has no ld-relay, find_ld_relay_namespaces()
    # just returns [] and the loop below is a no-op, so no separate flag is needed.
    relay_healthy = True
    relay_namespaces = find_ld_relay_namespaces(deployments_json)
    if not relay_namespaces:
        print("ld-relay: not found in any scanned namespace")
    for relay_ns in relay_namespaces:
        relay = check_ld_relay_status(args.kubectl_prefix, relay_ns)
        print("ld-relay (namespace: %s):" % relay_ns)
        print_relay_result(relay)
        healthy_here = relay.get("healthy", False) if relay.get("ok") else False
        service_broken = bool(relay.get("ok") and relay.get("healthy") and relay.get("service_reachable") is False)

        if service_broken:
            # Pod itself is fine and LD-connected -- restarting it fixes
            # nothing here, the problem is routing (Service/Endpoints), not
            # the process. Downstream services will show connection-refused
            # errors, but those don't match RESTART_CANDIDATE_PATTERNS (they're
            # retry-loop errors, not stuck-init errors), so they naturally
            # won't get restarted either -- correct, since restarting them
            # wouldn't help. Just flag it and move on to scanning.
            relay_healthy = False
            print("ld-relay recovery action: none -- this is a Service/Endpoints "
                  "problem, not a process problem; restarting will not help")
        elif not healthy_here:
            relay_healthy = False
            action, ok = restart_deployment(args.kubectl_prefix, relay_ns, "ld-relay", args.confirm)
            print("ld-relay recovery action: %s" % action)
            if args.confirm and ok and action == "restarted":
                print("Waiting for ld-relay rollout to complete...")
                rolled_out = wait_for_rollout(args.kubectl_prefix, relay_ns, "ld-relay",
                                               timeout_seconds=RELAY_RECOVERY_TIMEOUT_SECONDS)
                if not rolled_out:
                    print("ERROR: ld-relay rollout did not complete within %ds -- "
                          "aborting before touching any other service. Re-run this "
                          "script once ld-relay recovers." % RELAY_RECOVERY_TIMEOUT_SECONDS)
                    sys.exit(1)
                print("ld-relay rolled out -- waiting for it to actually reconnect "
                      "to LaunchDarkly (rollout success only means the pod passed "
                      "its readiness probe, not that it's LD-connected)...")
                recovered, last_relay = wait_for_relay_healthy(args.kubectl_prefix, relay_ns)
                if not recovered:
                    print("ERROR: ld-relay rolled out but never reached a healthy "
                          "connectionStatus within %ds -- aborting before touching "
                          "any other service (restarting downstream services would "
                          "be pointless while the relay itself is still broken). "
                          "Last status:" % RELAY_RECOVERY_TIMEOUT_SECONDS)
                    if last_relay:
                        print_relay_result(last_relay)
                    sys.exit(1)
                print("ld-relay confirmed healthy.")
                time.sleep(5)  # let the relay warm its own cache before dependents restart
        print("")

    services = find_ff_consuming_services(deployments_json, statefulsets_json)
    services = [s for s in services if s["name"] != "ld-relay"]

    for svc in services:
        svc["log_errors"] = check_service_log_errors(args.kubectl_prefix, svc, args.since, log_since_time)
        log_errors = svc["log_errors"]
        eligible = log_errors.get("restart_candidate") and log_errors.get("still_live") is True
        if eligible:
            svc["action"], _ = restart_deployment(
                args.kubectl_prefix, svc["namespace"], svc["name"], args.confirm,
                kind=svc.get("kind", "Deployment"),
            )

    print_services_result(services, verbose=args.verbose)

    restarted = [s for s in services if s.get("action") == "restarted"]
    if args.confirm and restarted:
        print("\nWaiting for %d restarted service(s) to roll out, then validating..." % len(restarted))
        for svc in restarted:
            wait_for_rollout(args.kubectl_prefix, svc["namespace"], svc["name"], kind=svc.get("kind", "Deployment"))
        time.sleep(10)  # let freshly-restarted clients finish their own init window before re-checking
        print("\n=== Post-restart validation ===")
        for svc in restarted:
            fresh_errors = check_service_log_errors(args.kubectl_prefix, svc, args.since, log_since_time)
            still_bad = fresh_errors.get("still_live") is True
            verdict = "STILL SHOWING THE ISSUE -- needs further investigation" if still_bad else "clear"
            print("  %s/%s: %s" % (svc["namespace"], svc["name"], verdict))

    if args.csv_out:
        write_csv(services, args.csv_out)
        print("\nWrote %s" % args.csv_out)


if __name__ == "__main__":
    main()
