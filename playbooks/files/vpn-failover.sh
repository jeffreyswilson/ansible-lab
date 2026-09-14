#!/usr/bin/env bash
# vpn-failover.sh
#
# Monitors the two AWS Site-to-Site VPN tunnels (aws-tunnel1 / aws-tunnel2)
# on this libreswan host and forces the shared eroute onto the standby
# tunnel when the currently active tunnel loses its IPsec SA.
#
# Context: both connections carry the identical traffic selector
# (10.50.0.0/16 <-> 10.100.0.0/16), so libreswan can only give one of
# them the eroute at a time -- static-routes-only, no BGP/ECMP to
# arbitrate concurrent use. This is expected active/standby behavior,
# not a defect. DPD (delay:10s, timeout:30s) is already configured on
# both connections and will detect a dead peer and attempt its own
# restart -- this script exists for the case where that restart does
# not result in either connection re-taking the eroute, and forces the
# issue explicitly rather than waiting indefinitely.

set -euo pipefail

TUNNELS=("aws-tunnel1" "aws-tunnel2")
POLL_INTERVAL=5      # seconds -- shorter than DPD timeout (30s) so a
                     # failure is caught close to when libreswan itself
                     # detects it, not on a separate slower cadence
LOG_TAG="vpn-failover"

log() {
    logger -t "$LOG_TAG" -- "$1"
    echo "$(date -Iseconds) $1"
}

get_erouted_conn() {
    # Prints the connection name currently holding the eroute (owner
    # != #0), or nothing if no connection currently holds it.
    ipsec status | awk '
        /^000 "aws-tunnel[0-9]+": .*erouted; eroute owner: #[0-9]+/ {
            if ($0 !~ /eroute owner: #0/) {
                match($0, /"aws-tunnel[0-9]+"/)
                print substr($0, RSTART+1, RLENGTH-2)
            }
        }
    '
}

standby_of() {
    local active="$1"
    for t in "${TUNNELS[@]}"; do
        if [[ "$t" != "$active" ]]; then
            echo "$t"
            return
        fi
    done
}

last_known_active=""

log "vpn-failover starting -- monitoring: ${TUNNELS[*]}"

while true; do
    active_conn="$(get_erouted_conn || true)"

    if [[ -n "$active_conn" ]]; then
        if [[ "$active_conn" != "$last_known_active" ]]; then
            log "Eroute held by $active_conn (was: ${last_known_active:-none})"
            last_known_active="$active_conn"
        fi
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Nothing currently holds the eroute.
    if [[ -z "$last_known_active" ]]; then
        # No baseline yet (e.g. fresh boot, both tunnels still
        # negotiating). Bring up the first tunnel explicitly rather
        # than assume a failure happened.
        target="${TUNNELS[0]}"
        log "No eroute owner and no prior baseline -- bringing up $target"
    else
        target="$(standby_of "$last_known_active")"
        log "Eroute lost on $last_known_active -- failing over to $target"
        # --down alone tears down the SA but does not release the
        # eroute -- confirmed empirically 9/14/26: a subsequent
        # --up on the standby fails ("cannot install eroute -- it is
        # in use for ...") until --unroute runs first.
        ipsec auto --down "$last_known_active" 2>&1 | logger -t "$LOG_TAG" || true
        ipsec auto --unroute "$last_known_active" 2>&1 | logger -t "$LOG_TAG" || true
    fi

    ipsec auto --up "$target" 2>&1 | logger -t "$LOG_TAG" || true

    sleep "$POLL_INTERVAL"
    new_active="$(get_erouted_conn || true)"
    if [[ "$new_active" == "$target" ]]; then
        log "Failover to $target confirmed"
        last_known_active="$target"
    else
        log "WARNING: failover to $target did not take -- current owner: '${new_active:-none}'"
        last_known_active=""
    fi

    sleep "$POLL_INTERVAL"
done
