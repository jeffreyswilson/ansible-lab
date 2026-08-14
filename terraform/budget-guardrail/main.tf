# terraform/budget-guardrail/main.tf
#
# Deliberately a separate Terraform root, state, and provider profile
# (budget-admin) from ../. This guardrail governs terraform-lab and must
# not be modifiable by terraform-lab itself -- see NOTES.md.
#
# terraform-lab (the IAM user referenced below by ARN/name) is managed
# in the sibling root one directory up. It is intentionally out of this
# root's state -- referenced by name only, never created or imported here.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "budget-admin"
}

resource "aws_iam_policy" "budget_deny" {
  name        = "terraform-lab-budget-deny"
  description = "Denies resource-creating actions on terraform-lab once budget threshold is hit"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Action = [
        "ec2:RunInstances",
        "ec2:CreateNatGateway",
        "ec2:CreateTransitGateway*",
        "ec2:CreateVpnConnection",
        "ec2:AllocateAddress"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_budgets_budget_action" "cap" {
  budget_name        = "MyLabBudgetCapsAt5"
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.budget_deny.arn
      users      = ["terraform-lab"]
    }
  }

  subscriber {
    address           = "fiction-clasp-barn@duck.com"
    subscription_type = "EMAIL"
  }

  execution_role_arn = aws_iam_role.budget_action_execution.arn
}

resource "aws_iam_role" "budget_action_execution" {
  name = "budget-action-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
    }]
  })
}
