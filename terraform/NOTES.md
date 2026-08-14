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
see career/stubs/aws_lab.md Decisions Log for the resulting pause/resume
guardrail (structural vs. hourly-billed split), not yet implemented.

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
