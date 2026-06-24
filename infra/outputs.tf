output "bucket_name" {
  description = "S3 bucket used for claims PDF input and JSON output."
  value       = aws_s3_bucket.claims_pdf.bucket
}

output "input_example_s3_uri" {
  description = "Example S3 URI for an input claims PDF."
  value       = "s3://${aws_s3_bucket.claims_pdf.bucket}/raw/sample-claim.pdf"
}

output "output_example_s3_uri" {
  description = "Expected S3 URI for the generated JSON output."
  value       = "s3://${aws_s3_bucket.claims_pdf.bucket}/output/sample-claim.json"
}

output "run_command" {
  description = "Example command for running the local Textract POC script."
  value       = "python run_textract.py ${aws_s3_bucket.claims_pdf.bucket} raw/sample-claim.pdf"
}

output "iam_policy_arn" {
  description = "IAM policy ARN for running the Textract POC."
  value       = aws_iam_policy.textract_poc.arn
}
