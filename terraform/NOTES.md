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
