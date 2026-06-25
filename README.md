# AWS Textract Claims PDF to JSON POC

Proof of concept for extracting structured claim data from a PDF with Amazon Textract.

This version keeps the architecture intentionally small:

1. Upload a claims PDF to S3 under `raw/`.
2. Run Textract document analysis for forms and tables.
3. Poll for completion.
4. Parse Textract blocks into lines, key-value fields, tables, and a simple claim JSON shape.
5. Save the generated JSON back to S3 under `output/`.

## Scope

Version 1 uses Terraform only for the AWS infrastructure needed by the local Python/Jupyter flow.

Included:

- S3 bucket for input PDFs and output JSON files
- S3 versioning
- S3 server-side encryption with AES256
- S3 public access blocking
- IAM policy for Textract and scoped S3 access
- Local Jupyter notebook workflow
- Synthetic sample claim PDF generator

Not included in version 1:

- Lambda
- Step Functions
- SNS or SQS
- DynamoDB
- OpenSearch
- Bedrock
- Human review workflow
- S3 event trigger

## Repository Layout

```text
.
|-- README.md
|-- aws_textract_claims_pdf_to_json_poc.md
|-- terraform_implementation_plan.md
|-- claims_pdf_to_json_textract_poc.ipynb
|-- sample-claim.pdf
|-- infra/
|   |-- versions.tf
|   |-- variables.tf
|   |-- main.tf
|   |-- outputs.tf
|   |-- terraform.tfvars.example
|   `-- .terraform.lock.hcl
`-- scripts/
    `-- generate_sample_claim_pdf.py
```

## Prerequisites

- AWS CLI configured with a profile that can create S3 buckets and IAM policies
- Terraform `>= 1.5.0`
- Python 3
- Jupyter
- Python packages:
  - `boto3`

If you are using AWS SSO, log in before running Terraform or the notebook:

```powershell
aws sso login --profile <your-profile>
aws sts get-caller-identity --profile <your-profile>
```

## Create the Sample PDF

The repo includes `sample-claim.pdf`. To regenerate it:

```powershell
python scripts\generate_sample_claim_pdf.py
```

The generated PDF is synthetic and does not contain real patient, provider, member, or claim data.

## Provision AWS Resources

From the Terraform folder:

```powershell
cd infra
terraform init
terraform plan -var-file="terraform.tfvars.example"
terraform apply -var-file="terraform.tfvars.example"
```

Terraform creates one S3 bucket and one IAM policy.

Useful outputs:

```powershell
terraform output bucket_name
terraform output input_example_s3_uri
terraform output output_example_s3_uri
terraform output iam_policy_arn
```

If `bucket_name` is empty in `terraform.tfvars.example`, Terraform derives a bucket name from the project name, AWS account ID, and AWS region.

## IAM Notes

The Terraform policy allows:

- `textract:StartDocumentAnalysis`
- `textract:GetDocumentAnalysis`
- `s3:ListBucket`
- `s3:GetObject` for `raw/*`
- `s3:PutObject` for `output/*`

Attach the generated IAM policy to the AWS identity used by your local AWS profile if that identity does not already have equivalent permissions.

Do not create or commit long-lived AWS access keys for this POC.

## Run the Notebook

Open:

```text
claims_pdf_to_json_textract_poc.ipynb
```

The notebook is organized as:

```text
Setup
Upload sample PDF
Start Textract
Poll status
Fetch blocks
Lines
Parse helpers
Key-values
Tables
Claim JSON
Save JSON
```

In the setup cell, set:

```python
aws_profile = "<your-profile>"
aws_region = "us-east-2"
bucket_name = "<terraform-output-bucket-name>"
input_key = "raw/sample-claim.pdf"
```

Then run the notebook cells in order. The notebook uploads `sample-claim.pdf`, starts Textract, waits for the job to complete, parses the response, builds the JSON output, and writes it to:

```text
s3://<bucket-name>/output/sample-claim.json
```

## Expected JSON Shape

The output is a simple claim-focused JSON structure:

```json
{
  "document": {
    "sourceBucket": "<bucket-name>",
    "sourceKey": "raw/sample-claim.pdf"
  },
  "claim": {
    "claimId": "CLM-2026-000123",
    "memberId": "M12345",
    "patientName": "John Smith",
    "providerName": "ABC Provider Clinic",
    "dateOfService": "01/15/2026",
    "totalBilledAmount": "$500.00",
    "totalPaidAmount": "$300.00",
    "serviceLines": []
  },
  "raw": {
    "keyValues": {},
    "tables": [],
    "lines": []
  }
}
```

Textract results can vary by document quality and layout, so treat this as a POC output shape rather than a production schema.

## Troubleshooting

If Terraform cannot find credentials, verify your AWS profile:

```powershell
aws sts get-caller-identity --profile <your-profile>
```

If the notebook raises `NoRegionError` or `NoCredentialsError`, make sure the setup cell creates clients through an explicit session:

```python
session = boto3.Session(profile_name=aws_profile, region_name=aws_region)
textract = session.client("textract")
s3 = session.client("s3")
```

If `terraform destroy` fails with `BucketNotEmpty`, the versioned S3 bucket still has object versions or delete markers. Empty the bucket, including versions and delete markers, before destroying the Terraform stack.

## Cleanup

After testing, remove generated S3 objects and destroy the Terraform-managed resources:

```powershell
cd infra
terraform destroy -var-file="terraform.tfvars.example"
```

Terraform state, local `.tfvars`, virtual environments, notebook checkpoints, and other local-only files are ignored by `.gitignore`.
