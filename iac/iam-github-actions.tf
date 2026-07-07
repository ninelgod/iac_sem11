resource "aws_iam_role_policy" "github_actions_frontend" {
  name = "${local.name_prefix}-github-actions-frontend"
  role = "gestorpagosg2-github-actions-deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${local.name_prefix}-web"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${local.name_prefix}-web/*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/E1CL9KCGY67CPM"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = module.kms.s3_key_arn
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
