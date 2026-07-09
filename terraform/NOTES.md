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
