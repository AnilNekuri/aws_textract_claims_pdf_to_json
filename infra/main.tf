data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  common_tags = merge(
    {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "poc"
    },
    var.tags
  )
}

resource "aws_s3_bucket" "claims_pdf" {
  bucket = local.bucket_name

  tags = merge(
    local.common_tags,
    {
      Name = local.bucket_name
    }
  )
}

resource "aws_s3_bucket_public_access_block" "claims_pdf" {
  bucket = aws_s3_bucket.claims_pdf.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "claims_pdf" {
  bucket = aws_s3_bucket.claims_pdf.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "claims_pdf" {
  bucket = aws_s3_bucket.claims_pdf.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "textract_poc" {
  statement {
    sid = "AllowTextractDocumentAnalysis"

    actions = [
      "textract:StartDocumentAnalysis",
      "textract:GetDocumentAnalysis",
    ]

    resources = ["*"]
  }

  statement {
    sid = "AllowListClaimsPocBucket"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.claims_pdf.arn,
    ]
  }

  statement {
    sid = "AllowReadInputPdfAndWriteOutputJson"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.claims_pdf.arn}/raw/*",
      "${aws_s3_bucket.claims_pdf.arn}/output/*",
    ]
  }
}

resource "aws_iam_policy" "textract_poc" {
  name        = "${var.project_name}-policy"
  description = "Allows the Textract claims PDF POC to read input PDFs and write JSON outputs."
  policy      = data.aws_iam_policy_document.textract_poc.json

  tags = local.common_tags
}
