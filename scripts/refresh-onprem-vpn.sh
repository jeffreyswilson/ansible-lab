#!/usr/bin/env bash
set -euo pipefail

# refresh-onprem-vpn.sh
#
# Pulls live tunnel data (outside IPs + PSKs) for aws_vpn_connection.onprem
# from AWS's own API and pushes it into the Ansible-managed on-prem config,
# then re-runs configure_ipsec.yml so the on-prem host's ipsec.conf/secrets
# match the CURRENT VPN connection rather than whatever connection existed
# at the last time this was populated by hand (9/9/26).
#
# WHY THIS EXISTS: aws_vpn_connection.onprem is now in terraform/Makefile's
# HOURLY_TARGETS. A destroy/resume cycle creates a NEW VPN connection with
# new tunnel outside IPs and freshly generated PSKs -- the on-prem host's
# config is static/templated data, nothing refreshes it automatically.
# Found via `make validate` showing both tunnels DOWN, LastChange: None,
# after a resume cycle -- neither side ever attempted a handshake because
# the on-prem host was still configured for the previous connection's
# endpoints. The 9/16/26 `-replace` verification of vpn-failover did NOT
# exercise this: that test replaced the instance but kept the same
# CGW/VPN connection (same tunnel endpoints, same PSKs), so this gap never
# surfaced there.
#
# [UNCERTAIN] -- NOT VERIFIED THIS SESSION. Everything below this line
# is a best-effort draft built from aws_lab.md's own prose record of the
# 9/9/26 manual setup, not from a live read of group_vars/onprem.yml,
# group_vars/onprem_vpn_secrets.yml, templates/ipsec.conf.j2, or
# inventory.ini. Specifically unconfirmed:
#   - the exact key names this script writes into group_vars/onprem.yml
#     and group_vars/onprem_vpn_secrets.yml match what ipsec.conf.j2 and
#     ipsec.secrets.j2 actually reference via Jinja {{ }}
#   - the exact XML path AWS uses inside CustomerGatewayConfiguration on
#     this VPN connection (schema below matches AWS's documented format,
#     not a live sample from this connection)
#   - whether inventory.ini needs the on-prem host's IP re-pointed here
#     too, or whether that's handled elsewhere
# Run with DRY_RUN=1 first (prints parsed values, writes nothing) and
# confirm against the actual files before trusting a real run.

REPO_ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$REPO_ROOT/terraform"
VAULT_PASS_FILE="$REPO_ROOT/.vault_pass"
GROUP_VARS_PLAIN="$REPO_ROOT/group_vars/onprem.yml"
GROUP_VARS_SECRETS="$REPO_ROOT/group_vars/onprem_vpn_secrets.yml"
DRY_RUN="${DRY_RUN:-0}"

echo "=== 1. Resolve live VPN connection ID from terraform state ==="
vpn_id=$(cd "$TF_DIR" && terraform state show aws_vpn_connection.onprem 2>/dev/null \
  | grep -E '^ {4}id +=' | awk -F'"' '{print $2}')
if [ -z "$vpn_id" ]; then
    echo "FATAL: aws_vpn_connection.onprem not in state. Run 'make resume' first." >&2
    exit 1
fi
echo "-> $vpn_id"

echo "=== 2. Pull live tunnel config from AWS ==="
cgw_config=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_id" \
  --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text)

if [ "$DRY_RUN" = "1" ]; then
    echo "-- raw CustomerGatewayConfiguration XML (DRY_RUN=1) --"
    echo "$cgw_config"
fi

# CustomerGatewayConfiguration is an XML document with two <ipsec_tunnel>
# blocks. Extract outside IP + PSK per tunnel via xmllint/xpath. This is
# AWS's documented schema shape -- verify against the DRY_RUN=1 output
# above before trusting the parsed values below.
t1_ip=$(echo "$cgw_config" | xmllint --xpath \
  'string(//ipsec_tunnel[1]/vpn_gateway/tunnel_outside_address/ip_address)' - 2>/dev/null)
t1_psk=$(echo "$cgw_config" | xmllint --xpath \
  'string(//ipsec_tunnel[1]/ike/pre_shared_key)' - 2>/dev/null)
t2_ip=$(echo "$cgw_config" | xmllint --xpath \
  'string(//ipsec_tunnel[2]/vpn_gateway/tunnel_outside_address/ip_address)' - 2>/dev/null)
t2_psk=$(echo "$cgw_config" | xmllint --xpath \
  'string(//ipsec_tunnel[2]/ike/pre_shared_key)' - 2>/dev/null)

for v in t1_ip t1_psk t2_ip t2_psk; do
    if [ -z "${!v}" ]; then
        echo "FATAL: failed to parse \$$v from CustomerGatewayConfiguration -- xpath likely wrong for this schema version. Re-run with DRY_RUN=1 and inspect the raw XML." >&2
        exit 1
    fi
done
echo "-> tunnel1 outside: $t1_ip / tunnel2 outside: $t2_ip (PSKs captured, not printed)"

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN=1 -- stopping before any file write or playbook run."
    exit 0
fi

echo "=== 3. Update plaintext tunnel params: $GROUP_VARS_PLAIN ==="
# [UNCERTAIN] key names below (tunnel1_outside_ip / tunnel2_outside_ip) are
# a guess at what ipsec.conf.j2 references -- confirm against the template
# before trusting this write.
yq -i ".tunnel1_outside_ip = \"$t1_ip\" | .tunnel2_outside_ip = \"$t2_ip\"" "$GROUP_VARS_PLAIN"

echo "=== 4. Re-encrypt PSKs: $GROUP_VARS_SECRETS ==="
tmp_secrets=$(mktemp)
trap 'rm -f "$tmp_secrets"' EXIT
cat > "$tmp_secrets" <<YAML
tunnel1_psk: "$t1_psk"
tunnel2_psk: "$t2_psk"
YAML
# [UNCERTAIN] key names above (tunnel1_psk / tunnel2_psk) are a guess at
# what ipsec.secrets.j2 references -- confirm against the template before
# trusting this write. Overwrites the existing vault file entirely; if it
# carries other keys beyond the two PSKs, merge instead of overwrite.
ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" \
  --output "$GROUP_VARS_SECRETS" "$tmp_secrets"

echo "=== 5. Re-run configure_ipsec.yml against the current on-prem host ==="
cd "$REPO_ROOT"
ansible-playbook -i inventory.ini playbooks/configure_ipsec.yml

echo "=== 6. Verify ==="
(cd "$TF_DIR" && make validate-tunnel)
