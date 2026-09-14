## Drift detection exercise (7/9/26)
Hand-edited aws_vpc.lab Name tag via AWS console.
`terraform plan` correctly diffed real-world state against declared
config and flagged the tag for correction. `terraform apply` reconciled
it back to HCL-declared value. Demonstrates plan-as-diff against
refreshed real-world state, not just the stored state file.

## Import exercise (7/9/26)
Created subnet manually via AWS console (10.100.2.0/24, terraform-lab-vpc).
Wrote matching aws_subnet resource block by hand. `terraform import` bound
the block to the real subnet ID; `terraform plan` confirmed zero diff --
hand-written declaration matched console-created reality exactly.
Demonstrates brownfield adoption: reconstructing declared intent from
live infrastructure state, verified rather than assumed correct.

## Mothball recovery (8/11/26)
VM booted first time in 30+ days. `terraform plan` against the existing
state showed 15-to-add, 0-to-change, 0-to-destroy -- confirmed the prior
session's `terraform destroy` had removed everything (VPC, subnets, IGW,
NAT, EIP, route tables, SG, IAM role/profile, test instance), not just
the Phase 2b subset intended. Full re-apply rebuilt all 15 resources
clean. Demonstrates the gap between "destroy after each session" as
written and what it actually costs when the destroy wasn't scoped --
see personal tracking doc for the resulting pause/resume guardrail
(structural vs. hourly-billed split), not yet implemented.

## outputs.tf expansion (8/11/26)
Original file only declared vpc_id/subnet_id. Added 8 more outputs
covering every Phase 1-2b resource, then 2 more for Phase 3 VPC2
(vpc2_id, vpc2_subnet_id). `terraform output` now surfaces all resource
IDs in one call instead of per-resource `terraform state show`.

## Phase 3 step 1 -- VPC2 (8/11/26)
New file vpc2.tf: aws_vpc.vpc2 (10.200.0.0/16) + aws_subnet.vpc2
(10.200.1.0/24), same AZ as VPC1, both CIDRs from new variables
(vpc2_cidr, vpc2_subnet_cidr) rather than hardcoded -- matches the
existing variable-driven convention from Phase 2 step 3. Applied clean:
vpc-05b451f438899da7f, subnet-0f094922069cd59f8. TGW resource and
attachments (rest of Phase 3 step 1) not yet built.

## Make: default recipe-line isolation, and why HOURLY_TARGETS is a single source of truth (8/14/26)
Every Makefile recipe line runs as its own separate shell invocation by default --
state from one line (a `cd`, a shell variable) does not carry to the next unless
lines are joined with a trailing `\`. This is why `destroy-full`'s `read -p` and
its `[ ]` confirmation check must share one backslash-joined line: `read` sets a
shell variable that a separate, unjoined recipe line would never see.

`HOURLY_TARGETS` is defined once and referenced by both `pause` and `resume` for
the same reason normalized SQL avoids duplicate rows across tables: one point of
authority, one point of update. Two independent copies of the same `-target`
list would drift the first time a new hourly resource (a VPN connection, Phase 4+)
gets added to one recipe and forgotten in the other.

`destroy-full` requires typing the literal string `destroy everything`, not a
plain `y/N`. This exists because Terraform's own `yes` confirmation had already
proven, empirically, in this project, that it doesn't reliably stop a reflex-typed
action -- an unqualified `terraform destroy` was run mid-session on 8/13/26 despite
dozens of correct, deliberate `yes` confirmations earlier that same session. A
novel string breaks the autopilot that a repeated keystroke does not.

Lesson for extending this Makefile: any new hourly-billed resource type goes into
`HOURLY_TARGETS` only, never duplicated into individual recipes. Any new
irreversible/high-blast-radius action gets the same typed-confirmation treatment
as `destroy-full`, not a bare `yes`/`y-N` gate.

## IAM: a case-typo accidentally enforced the right self-permission boundary (8/14/26)
budget-admin's own scoped policy (BudgetGuardrailAdmin) grants
iam:GetPolicy/CreatePolicyVersion/etc. only against resources matching
`arn:...policy/*budget*` -- lowercase. The policy's own name is
`BudgetGuardrailAdmin` -- capital B. IAM resource-ARN matching is a literal,
case-sensitive string match, so the pattern does not match the policy's own ARN.
Attempting `terraform import` of that policy under budget-admin's own
credentials fails with AccessDenied.

Rather than widen the pattern to fix this, the mismatch is being kept
deliberately (terraform/budget-guardrail/iam.tf.reference.txt documents this).
Widening it would let budget-admin read and version its own attached policy --
a step toward self-modification, the exact shape of privilege escalation the
budget-admin/terraform-lab identity split was built to prevent in the first
place (a principal that can arm a kill-switch against another principal should
not also be able to disarm or loosen its own grant).

Lesson: an accidental scoping gap isn't always a bug to fix. Before widening any
IAM Resource pattern to make an error go away, check whether the narrower scope
is incidentally enforcing a boundary you actually want -- in this case, root
manages budget-admin's own rights; budget-admin manages the guardrail pointed at
terraform-lab; neither identity manages itself.

## Terraform -target: destroy's dependency walk isn't mirrored on create (8/14/26)

`terraform destroy -target=X` automatically pulls in every resource that
*references* X (a downstream consumer), since leaving those pointing at a
soon-to-not-exist ID would be invalid. Confirmed empirically: targeting only
the 5 original HOURLY_TARGETS for `make pause` destroyed 10 resources --
Terraform correctly cascaded to both TGW route table associations,
propagations, and `aws_route.private_default`, none of which were named as
targets.

`terraform apply -target=X` does NOT walk the same direction. It only pulls
in resources X itself *depends on* (upstream prerequisites), not resources
that depend on X. Confirmed empirically: the first `make plan-resume`
attempt, using the original 5-target list, showed only 5 creates -- the four
TGW-side resources and `private_default` were silently absent. Running
`make resume` as originally written would have recreated both TGW
attachments with new IDs but left them unassociated and unpropagated, and
left VPC1 with no default route at all -- a partially-resumed, silently
broken state.

Fix: HOURLY_TARGETS now explicitly lists all 10 resources (both directions
of the dependency graph), not just the 5 that literally bill hourly. Verified
via full pause -> plan-resume (10 adds, correct) -> resume -> unscoped
`terraform plan` (zero drift) -> live AWS CLI checks (route tables, TGW
propagation) all clean.

Lesson: don't assume `-target`'s dependency-following behavior is symmetric
between destroy and create/apply. Test the actual resume path with
`plan-resume` before trusting a targeted pause/resume pair, even when the
destroy side looked correct -- correct destroy behavior says nothing about
whether resume will be complete.

## BudgetGuardrailAdmin's final policy required 6 iterations (8/17/26)

See `terraform/budget-guardrail/iam.tf.reference` for the full account.
Each of iam:CreateRole, PassRole+PassedToService condition,
ListRolePolicies, ListAttachedRolePolicies, ListInstanceProfilesForRole,
and budgets:ListTagsForResource was discovered by running a real
`terraform apply` and reading the resulting AccessDenied, not designed
up front. Treat a newly-scoped IAM identity's first deploy as a
discovery pass, not a validation pass.

## Terraform modify vs. replace: cloud-init skips user_data on same instance ID (9/12/26)

Modified `aws_instance.test`'s `user_data` (added SSM/SSH debug logic)
and applied normally -- Terraform reported a successful in-place
modify, same instance ID, no errors. SSM registration never appeared
(`describe-instance-information` returned empty) and the password/SSH
changes never took effect either.

Ruled out first, all clean: NAT gateway state (`available`), security
group egress (0.0.0.0/0 open), IAM, AMI. Root cause: cloud-init tracks
first-boot completion per instance ID (`/var/lib/cloud/instance/`).
Since the instance ID never changed (a modify, not a destroy/create),
cloud-init saw "already initialized for this identity" on the
stop/start cycle triggered by the apply, and **silently skipped
`user_data` entirely** -- it never ran, not ran-and-failed. The same
root cause explained both symptoms at once.

Fix: `terraform apply -replace="aws_instance.test"` -- forces a
genuine destroy/create regardless of whether any argument changed,
guaranteeing a new instance ID and a real first boot. Confirmed: the
fresh instance registered with SSM cleanly (`PingStatus: Online`)
within seconds of boot.

Lesson: a `user_data` change applied as a same-ID modify is not
equivalent to a fresh boot for cloud-init's purposes, even though
Terraform's apply succeeds cleanly and reports no errors. This is the
most dangerous failure shape -- looks like it worked, does nothing.
Use `-replace` (or any change that forces a genuine destroy/create)
whenever `user_data` itself is what needs to re-run.

## VPN Tunnel Failover Monitor (9/14/26)

Added a systemd-managed script (`playbooks/files/vpn-failover.sh`)
that watches which tunnel currently holds the eroute and forces
failover to the standby tunnel when the active one is lost.

Both tunnels share an identical traffic selector, so libreswan will
only ever give the eroute to one connection at a time -- this is the
expected active/standby posture of a static-routing (no BGP/ECMP)
two-tunnel VPN, not a bug.

Two real findings, worth recording for anyone testing on a similar
libreswan build (4.12):

1. `ipsec down` / `ipsec up` are not valid commands on this build.
   `ipsec --help` lists the actual subcommand surface -- the correct
   invocation is `ipsec auto --down <conn>` / `ipsec auto --up <conn>`.
2. `ipsec auto --down` tears down the IKE/IPsec state but does **not**
   release the eroute. Bringing up the standby connection immediately
   after fails with `cannot install eroute -- it is in use for
   "<old-conn>"`. `ipsec auto --unroute <conn>` must run between the
   `--down` and the standby's `--up`.

Tested by forcing the active tunnel down (`ipsec auto --down
aws-tunnel1`) and confirming the monitor detected the loss and brought
up the standby within one poll cycle (~5s), fully automatic.

### Deploy

Not yet wired into the Ansible playbook -- deployed manually:

```
scp playbooks/files/vpn-failover.sh playbooks/files/vpn-failover.service ec2-user@<onprem-ip>:/tmp/
ssh ec2-user@<onprem-ip>
sudo install -m 755 /tmp/vpn-failover.sh /usr/local/bin/vpn-failover.sh
sudo cp /tmp/vpn-failover.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vpn-failover.service
```
