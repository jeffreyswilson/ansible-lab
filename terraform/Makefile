TF := terraform
AWS := aws

HOURLY_TARGETS := \
	-target=aws_instance.test \
	-target=aws_nat_gateway.lab \
	-target=aws_eip.nat \
	-target=aws_ec2_transit_gateway_vpc_attachment.vpc1 \
	-target=aws_ec2_transit_gateway_vpc_attachment.vpc2 \
	-target=aws_ec2_transit_gateway_route_table_association.vpc1 \
	-target=aws_ec2_transit_gateway_route_table_association.vpc2 \
	-target=aws_ec2_transit_gateway_route_table_propagation.vpc1 \
	-target=aws_ec2_transit_gateway_route_table_propagation.vpc2 \
	-target=aws_route.private_default

MUST_BE_IGNORED := .vault_pass \
	terraform/terraform.tfstate terraform/terraform.tfstate.backup \
	terraform/budget-guardrail/terraform.tfstate terraform/budget-guardrail/terraform.tfstate.backup \
	containerlab/clab-frr-lab/.tls/ca/ca.key

.PHONY: plan-pause pause plan-resume resume plan-full apply-full destroy-full state \
	validate validate-plan validate-tunnel validate-routes secrets-check

plan-pause:
	$(TF) plan -destroy $(HOURLY_TARGETS)

pause:
	$(TF) destroy $(HOURLY_TARGETS)

plan-resume:
	$(TF) plan $(HOURLY_TARGETS)

resume:
	$(TF) apply $(HOURLY_TARGETS)

plan-full:
	$(TF) plan

apply-full:
	$(TF) apply

destroy-full:
	@echo "WARNING: this destroys every managed resource, structural included."
	@echo "Confirm this is intentional -- pause/resume should use 'make pause' instead."
	@read -p "Type 'destroy everything' to proceed: " confirm; \
	[ "$$confirm" = "destroy everything" ] || (echo "Aborted."; exit 1)
	$(TF) destroy

state:
	$(TF) state list

# ---------------------------------------------------------------------------
# validate: live-state checks that terraform's own plan/apply cycle does not
# cover -- VPN tunnel telemetry (not terraform-tracked at all) and TGW RIB
# content (propagated-vs-blackhole is a control-plane lookup outcome, not an
# attribute terraform diffs). validate-plan covers everything terraform DOES
# track (including the onprem/CGW ForceNew-on-IP-change case, since CGW's
# ip_address is computed from aws_instance.onprem's live public_ip and a
# refresh will surface that as drift on its own).
#
# Uses whatever AWS CLI credentials/AWS_PROFILE are active in your shell --
# this does NOT inherit the provider `profile =` argument from the .tf files.
# Confirm AWS_PROFILE matches before relying on output.
#
# [UNCERTAIN] id-line extraction below assumes `terraform state show`
# indents top-level resource attributes at exactly 4 spaces on this
# terraform version. Test `make validate-tunnel` alone first; if it prints
# nothing where a resource exists, the grep pattern needs adjusting to match
# actual output alignment.
# ---------------------------------------------------------------------------

validate: validate-plan validate-tunnel validate-routes

validate-plan:
	@echo "=== 1. Live-refreshed plan: state vs AWS reality ==="
	@$(TF) plan -detailed-exitcode -no-color; rc=$$?; \
	if [ $$rc -eq 0 ]; then \
		echo "-> No drift."; \
	elif [ $$rc -eq 2 ]; then \
		echo "-> DRIFT: live AWS differs from what terraform expects. Review plan above before pause/resume."; \
	else \
		echo "-> terraform plan itself failed (exit $$rc)."; exit 1; \
	fi

validate-tunnel:
	@echo "=== 2. VPN tunnel telemetry (not terraform-tracked) ==="
	@vpn_id=$$($(TF) state show aws_vpn_connection.onprem 2>/dev/null | grep -E '^ {4}id +=' | awk -F'"' '{print $$2}'); \
	if [ -z "$$vpn_id" ]; then \
		echo "-> aws_vpn_connection.onprem not in state -- skipped."; \
	else \
		echo "-> checking $$vpn_id"; \
		$(AWS) ec2 describe-vpn-connections --vpn-connection-ids $$vpn_id \
		  --query 'VpnConnections[0].VgwTelemetry[*].{OutsideIP:OutsideIpAddress,Status:Status,LastChange:LastStatusChangeTime}' \
		  --output table; \
	fi

validate-routes:
	@echo "=== 3. TGW route table content: propagated CIDRs, active vs blackhole ==="
	@rtb_id=$$($(TF) state show aws_ec2_transit_gateway_route_table.lab 2>/dev/null | grep -E '^ {4}id +=' | awk -F'"' '{print $$2}'); \
	if [ -z "$$rtb_id" ]; then \
		echo "-> aws_ec2_transit_gateway_route_table.lab not in state -- skipped."; \
	else \
		echo "-> checking $$rtb_id"; \
		for cidr in 10.200.0.0/16 10.50.0.0/16; do \
			echo "-- $$cidr --"; \
			$(AWS) ec2 search-transit-gateway-routes --transit-gateway-route-table-id $$rtb_id \
			  --filters "Name=type,Values=propagated" \
			  --query "Routes[?DestinationCidrBlock=='$$cidr'].{CIDR:DestinationCidrBlock,State:State,Type:Type}" \
			  --output table; \
		done; \
	fi

# ---------------------------------------------------------------------------
# secrets-check: (1) every group_vars/*_secrets.yml tracked by git must be
# ansible-vault encrypted -- fails loud if any is plaintext. (2) a heuristic
# scan of every OTHER tracked file for a PSK/secret-looking quoted value
# (16+ base64/hex-alphabet chars), to catch a value accidentally copy-pasted
# outside the vault. Heuristic, not a real secret scanner -- catches the
# specific shape this project's own PSK/vault pattern would leak as, nothing
# more general. Consider gitleaks/trufflehog as a follow-on if this repo's
# secret surface grows past one vault file.
#
# Run from repo root or terraform/ -- resolves the root itself.
# ---------------------------------------------------------------------------

secrets-check:
	@repo_root=$$(git rev-parse --show-toplevel); \
	echo "=== secrets-check: vault encryption + leak scan ==="; \
	files=$$(cd "$$repo_root" && ls group_vars/*_secrets.yml 2>/dev/null); \
	fail=0; \
	if [ -z "$$files" ]; then \
		echo "-> No git-tracked *_secrets.yml files under group_vars/ -- nothing to check."; \
	else \
		for f in $$files; do \
			hdr=$$(head -c 15 "$$repo_root/$$f"); \
			if [ "$$hdr" = '$$ANSIBLE_VAULT;' ]; then \
				echo "-> OK: $$f is vault-encrypted."; \
			else \
				echo "-> FAIL: $$f does not start with an ansible-vault header -- looks plaintext."; \
				fail=1; \
			fi; \
		done; \
	fi; \
	echo "-- scanning tracked files outside the vault file(s) for raw secret-looking values --"; \
	hits=$$(git -C "$$repo_root" grep --untracked -nIE '(PSK|psk|secret)[^=\"'"'"']*["'"'"'][A-Za-z0-9+/=]{16,}["'"'"']' -- ':!group_vars/*_secrets.yml' 2>/dev/null); \
	if [ -n "$$hits" ]; then \
		echo "-> FAIL: possible raw secret material outside the vault file(s):"; \
		echo "$$hits"; \
		fail=1; \
	else \
		echo "-> No raw-looking secret values found outside the vault file(s)."; \
	fi; \
	echo "-- confirming known-sensitive paths are git-ignored, not trackable --"; \
	for p in $(MUST_BE_IGNORED); do \
		full="$$repo_root/$$p"; \
		if [ ! -e "$$full" ]; then \
			echo "-> n/a: $$p does not exist."; \
		elif git -C "$$repo_root" check-ignore -q -- "$$p"; then \
			echo "-> OK: $$p is ignored."; \
		else \
			echo "-> FAIL: $$p exists and is NOT git-ignored -- must not be trackable."; \
			fail=1; \
		fi; \
	done; \
	[ $$fail -eq 0 ] || (echo "secrets-check FAILED"; exit 1)

