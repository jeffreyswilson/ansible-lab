# terraform/budget-guardrail/execution_role.tf

resource "aws_iam_role_policy" "budget_action_execution" {
  name = "budget-action-execution-policy"
  role = aws_iam_role.budget_action_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy"
      ]
      Resource = "arn:aws:iam::529517534524:user/terraform-lab"
    }]
  })
}
