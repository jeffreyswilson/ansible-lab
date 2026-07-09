## Drift detection exercise (7/9/26)
Hand-edited aws_vpc.lab Name tag via AWS console.
`terraform plan` correctly diffed real-world state against declared
config and flagged the tag for correction. `terraform apply` reconciled
it back to HCL-declared value. Demonstrates plan-as-diff against
refreshed real-world state, not just the stored state file.
