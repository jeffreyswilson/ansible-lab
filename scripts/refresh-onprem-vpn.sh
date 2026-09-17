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
# CONFIRMED 9/17/26 against a live read of templates/ipsec.conf.j2,
# templates/ipsec.secrets.j2, and group_vars/onprem.yml (group_vars/
# onprem_vpn_secrets.yml is vault-encrypted and was not decrypted -- key
# names there are inferred from what ipsec.secrets.j2 actually looks up,
# not read directly). Two real mismatches found and fixed in this version:
#   - group_vars/onprem.yml: ipsec.conf.j2 reads tunnel.aws_outside_ip per
#     entry in the vpn_tunnels[] list (matched by .id), NOT flat
#     tunnel1_outside_ip/tunnel2_outside_ip keys. Fixed below.
#   - group_vars/onprem_vpn_secrets.yml: ipsec.secrets.j2 does
#     lookup('vars', 'onprem_vpn_tunnel' ~ tunnel.id ~ '_psk'), i.e. it
#     needs onprem_vpn_tunnel1_psk / onprem_vpn_tunnel2_psk, NOT
#     tunnel1_psk / tunnel2_psk. Fixed below.
#
# CONFIRMED 9/17/26: xpath verified against a live DRY_RUN=1 sample from
# vpn-0727316f0c8a7ddb4 -- correctly extracts the vpn_gateway (AWS) side's
# tunnel_outside_address per tunnel, matching AWS's documented schema.
#
# RESOLVED 9/17/26: inventory.ini DOES need the on-prem host's IP
# re-pointed every cycle -- aws_eip.onprem is one of the 17
# HOURLY_TARGETS, destroyed/recreated on every pause/resume. Handled
# automatically now in Step 2.
#
# STILL UNCONFIRMED [UNCERTAIN]:
#   - whether group_vars/onprem_vpn_secrets.yml carries any key beyond the
#     two PSKs -- it's opaque ciphertext and playbooks/configure_ipsec.yml
#     / inventory.ini were not read this session. This script's Step 4
#     overwrites that file entirely; if a third key exists and something
#     else consumes it, this drops it silently.
#   - terraform state show's attribute indent (Step 1's grep assumes 4
#     spaces, same assumption terraform/Makefile's validate-tunnel/
#     validate-routes targets flag as unconfirmed)
#
# Run with DRY_RUN=1 first (prints parsed values, writes nothing) and
# confirm against the actual files before trusting a real run. NOTE:
# DRY_RUN=1 prints the raw CustomerGatewayConfiguration XML, which
# includes both PSKs in the clear -- that's by design (you need to see
# them to confirm the xpath is grabbing the right value), but know it's
# going to your terminal.

REPO_ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$REPO_ROOT/terraform"
# NOTE 9/17/26: vault password resolution is left to ansible.cfg's
# vault_password_file setting -- no VAULT_PASS_FILE var needed here.
# See Step 5 for why passing it explicitly here caused a failure.
GROUP_VARS_PLAIN="$REPO_ROOT/group_vars/onprem.yml"
GROUP_VARS_SECRETS="$REPO_ROOT/group_vars/onprem_vpn_secrets.yml"
DRY_RUN="${DRY_RUN:-0}"

echo "=== 1. Resolve live VPN connection ID from terraform state ==="
# FIXED 9/17/26: the original one-liner combined the terraform call, grep,
# and awk into a single command substitution under set -e + pipefail. Any
# failure in that pipe (terraform state show erroring OR grep matching
# nothing) killed the script silently at the assignment itself -- the
# FATAL messages below were unreachable dead code. Split into two checked
# steps so each failure mode actually reports.
set +e
vpn_state_output=$(cd "$TF_DIR" && terraform state show aws_vpn_connection.onprem 2>&1)
tf_rc=$?
set -e
if [ $tf_rc -ne 0 ]; then
    echo "FATAL: 'terraform state show aws_vpn_connection.onprem' failed (exit $tf_rc) -- likely not in state. Run 'make resume' first. Raw output:" >&2
    echo "$vpn_state_output" >&2
    exit 1
fi
vpn_id=$(echo "$vpn_state_output" | grep -E '^ {4}id +=' | awk -F'"' '{print $2}')
if [ -z "$vpn_id" ]; then
    echo "FATAL: resource is in state but 'id' could not be parsed -- indent/format assumption (4 spaces) may be wrong for this terraform version. Raw output:" >&2
    echo "$vpn_state_output" >&2
    exit 1
fi
echo "-> $vpn_id"

echo "=== 2. Sync inventory.ini onprem host IP ==="
# ADDED 9/17/26: aws_eip.onprem is one of the 17 HOURLY_TARGETS -- it is
# destroyed and recreated on every pause/resume, so the on-prem host gets
# a NEW public IP every cycle, not just a new VPN connection. This bit
# this session directly (SSH timeout against a stale inventory.ini entry,
# traced and fixed by hand before this step existed).
# outputs.tf's onprem_public_ip is CONFIRMED STALE this session -- it
# lags the EIP association by one refresh (matches the 9/16/26 Decisions
# Log "one-refresh drift" entry, which called it benign/self-correcting;
# it does not self-correct within this script's runtime). onprem_eip is
# the confirmed-correct source, verified twice today against
# describe-instances/describe-addresses directly.
set +e
onprem_ip=$(cd "$TF_DIR" && terraform output -raw onprem_eip 2>&1)
tf_out_rc=$?
set -e
if [ $tf_out_rc -ne 0 ] || [ -z "$onprem_ip" ]; then
    echo "FATAL: 'terraform output -raw onprem_eip' failed or returned empty (exit $tf_out_rc). Raw output:" >&2
    echo "$onprem_ip" >&2
    exit 1
fi
INVENTORY_FILE="$REPO_ROOT/inventory.ini"
if ! grep -q '^onprem-sim ansible_host=' "$INVENTORY_FILE"; then
    echo "FATAL: inventory.ini has no 'onprem-sim ansible_host=' line to update -- format changed since this script was written? Not editing blind." >&2
    exit 1
fi
sed -i "s/^onprem-sim ansible_host=.*/onprem-sim ansible_host=$onprem_ip/" "$INVENTORY_FILE"
echo "-> inventory.ini onprem-sim ansible_host = $onprem_ip"

echo "=== 3. Pull live tunnel config from AWS ==="
cgw_config=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_id" \
  --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text)

if [ "$DRY_RUN" = "1" ]; then
    echo "-- raw CustomerGatewayConfiguration XML (DRY_RUN=1) --"
    echo "$cgw_config"
fi

# CustomerGatewayConfiguration is an XML document with two <ipsec_tunnel>
# blocks. Extract outside IP + PSK per tunnel via xmllint/xpath.
# CONFIRMED 9/17/26 against a live sample from vpn-0727316f0c8a7ddb4: xpath
# correctly pulls the vpn_gateway (AWS) side's tunnel_outside_address, not
# the customer_gateway side -- matches AWS's documented schema.
#
# FIXED 9/17/26: same bug class as Step 1. The four xmllint calls were
# individually wrapped in 2>/dev/null inside bare command substitutions
# under set -e/pipefail -- a missing xmllint binary or any one bad xpath
# killed the script silently, no message, and gave no indication which of
# the four extractions failed (this is exactly what happened before
# libxml2-utils was installed). extract_xpath() decouples each call from
# set -e so a failure reports which xpath failed and why before exiting.
extract_xpath() {
    local xpath="$1"
    local val rc
    set +e
    val=$(echo "$cgw_config" | xmllint --xpath "$xpath" - 2>&1)
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
        echo "FATAL: xmllint failed (exit $rc) extracting '$xpath'. Is xmllint/libxml2-utils installed? Raw output:" >&2
        echo "$val" >&2
        exit 1
    fi
    echo "$val"
}

t1_ip=$(extract_xpath 'string(//ipsec_tunnel[1]/vpn_gateway/tunnel_outside_address/ip_address)')
t1_psk=$(extract_xpath 'string(//ipsec_tunnel[1]/ike/pre_shared_key)')
t2_ip=$(extract_xpath 'string(//ipsec_tunnel[2]/vpn_gateway/tunnel_outside_address/ip_address)')
t2_psk=$(extract_xpath 'string(//ipsec_tunnel[2]/ike/pre_shared_key)')

for v in t1_ip t1_psk t2_ip t2_psk; do
    if [ -z "${!v}" ]; then
        echo "FATAL: \$$v parsed as empty -- xmllint ran cleanly but matched nothing. Re-run with DRY_RUN=1 and inspect the raw XML; the xpath may be wrong for this schema version." >&2
        exit 1
    fi
done
echo "-> tunnel1 outside: $t1_ip / tunnel2 outside: $t2_ip (PSKs captured, not printed)"

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN=1 -- stopping before any file write or playbook run."
    exit 0
fi

echo "=== 4. Update plaintext tunnel params: $GROUP_VARS_PLAIN ==="
# FIXED 9/17/26: ipsec.conf.j2 reads vpn_tunnels[].aws_outside_ip per entry,
# matched by .id -- not flat tunnel1_outside_ip/tunnel2_outside_ip keys.
# Update the two list entries in place instead.
yq -i "(.vpn_tunnels[] | select(.id == 1) | .aws_outside_ip) = \"$t1_ip\" | (.vpn_tunnels[] | select(.id == 2) | .aws_outside_ip) = \"$t2_ip\"" "$GROUP_VARS_PLAIN"

echo "=== 5. Re-encrypt PSKs: $GROUP_VARS_SECRETS ==="
tmp_secrets=$(mktemp)
trap 'rm -f "$tmp_secrets"' EXIT
cat > "$tmp_secrets" <<YAML
onprem_vpn_tunnel1_psk: "$t1_psk"
onprem_vpn_tunnel2_psk: "$t2_psk"
YAML
# FIXED 9/17/26: ipsec.secrets.j2 does lookup('vars', 'onprem_vpn_tunnel' ~
# tunnel.id ~ '_psk') -- variable names must be onprem_vpn_tunnel1_psk /
# onprem_vpn_tunnel2_psk, not tunnel1_psk / tunnel2_psk.
# [UNCERTAIN, unresolved]: this overwrites the existing vault file entirely.
# The templates read this session reference only these two keys, but
# playbooks/configure_ipsec.yml and inventory.ini were not read -- if a
# third key exists in the current vault file and is consumed elsewhere,
# this drops it silently. Confirm before running for real if that's a
# live concern.
# FIXED 9/17/26: ansible.cfg already sets vault_password_file = .vault_pass,
# which registers vault-id "default" for every ansible-vault invocation.
# Also passing --vault-password-file here (unlabeled) registered a SECOND
# vault-id also named "default" -- same file, same content, but
# ansible-vault saw two id-"default" sources and refused to pick one
# ("vault-ids default,default are available to encrypt"). ansible.cfg
# alone is sufficient since this script always runs from $REPO_ROOT.
ansible-vault encrypt \
  --output "$GROUP_VARS_SECRETS" "$tmp_secrets"

echo "=== 6. Re-run configure_ipsec.yml against the current on-prem host ==="
cd "$REPO_ROOT"
ansible-playbook -i inventory.ini playbooks/configure_ipsec.yml

echo "=== 7. Verify ==="
(cd "$TF_DIR" && make validate-tunnel)
