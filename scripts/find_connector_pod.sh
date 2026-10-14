#!/bin/bash
# orion:begin
# name: Find Connector Pod
# category: Connectors
# runs_on: DA-master
# mode: read-only
# description: Find connector pod by connector ID; prints the matching pod and a ready-to-run `kubectl exec` command.
# orion:end

# Find which log-collector-master pod is currently running a given connector ID.
#
# Usage (on the DA master node, after `sudo su`):
#   1. Open this file and copy everything.
#   2. Paste it into the terminal and press enter.
#   3. Enter the connector ID when prompted.
#   4. It prints the matching pod plus a ready-to-run `kubectl exec` command.

find_connector_pod() {
    local ns="default"
    local prefix="log-collector-master-grp"
    local container="log-collector-master"
    local cid

    read -rp "Enter the connector ID: " cid </dev/tty
    cid="${cid//[[:space:]]/}"
    if [[ -z "$cid" ]]; then
        echo "No connector ID entered. Aborting." >&2
        return 1
    fi

    echo "Searching $prefix pods in namespace '$ns' for connector $cid ..." >&2

    local tmp
    tmp="$(mktemp)"

    kubectl get pods -n "$ns" --no-headers 2>/dev/null \
        | awk -v p="$prefix" '$1 ~ p {print $1}' \
        | xargs -P 20 -I {} bash -c '
            pod="$1"; ns="$2"; cid="$3"; container="$4"; tmp="$5"
            # ps runs INSIDE the pod; grep runs HERE on the master node,
            # so the grep process is never visible to the pod ps (no self-match).
            if kubectl exec -c "$container" -i "$pod" -n "$ns" -- ps -e -o args 2>/dev/null \
                 | grep -q -- "--id $cid"; then
                echo "$pod" >> "$tmp"
            fi
        ' _ {} "$ns" "$cid" "$container" "$tmp"

    local matches
    mapfile -t matches < "$tmp"
    rm -f "$tmp"

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "No pod found running connector $cid." >&2
        echo "Check the ID, or the connector may not be currently running or runs on sensor." >&2
        return 1
    fi

    if [[ ${#matches[@]} -gt 1 ]]; then
        echo "WARNING: connector $cid matched multiple pods:" >&2
        printf '  %s\n' "${matches[@]}" >&2
    fi

    local pod="${matches[0]}"
    echo
    echo "Connector $cid is running on pod:"
    echo "  $pod"
    echo
    echo "Enter the pod with:"
    echo "  kubectl exec -it $pod -n $ns -- bash"
    echo
}

find_connector_pod
