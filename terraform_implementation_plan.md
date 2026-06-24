# Terraform Implementation Plan: AWS Textract Claims PDF POC

## Goal

Provision the AWS resources needed for the simple Textract POC described in `aws_textract_claims_pdf_to_json_poc.md`.

The POC flow remains:

```text
S3 PDF Upload
    |
    v
Local Python script
    |
    v
Textract StartDocumentAnalysis
    |
    v
Textract GetDocumentAnalysis
    |
    v
Parse Textract Blocks
    |
    v
Generate Structured Claims JSON
    |
    v
Save JSON to S3
```

Do not add these in version 1:

```text
Lambda
Step Functions
SNS
SQS
DynamoDB
OpenSearch
Bedrock
Human review workflow
S3 event trigger
```

Terraform should only create the infrastructure needed by the local Python script.

---

## Terraform Scope

Terraform should provision:

1. S3 bucket for input PDFs and output JSON files
2. IAM policy for Textract and S3 access
3. Optional IAM user for local POC execution
4. Safe bucket defaults such as encryption, versioning, and public access blocking
5. Outputs that make the POC easy to run

---

## Suggested Folder Structure

```text
claims-textract-simple/
  README.md
  requirements.txt
  run_textract.py

  infra/
    main.tf
    variables.tf
    outputs.tf
    versions.tf
    terraform.tfvars.example
```

---

## Terraform Resources

### 1. S3 Bucket

Create one S3 bucket for both PDF inputs and JSON outputs.

Example paths:

```text
s3://<bucket-name>/raw/sample-claim.pdf
s3://<bucket-name>/output/sample-claim.json
```

Recommended resources:

```text
aws_s3_bucket
aws_s3_bucket_versioning
aws_s3_bucket_server_side_encryption_configuration
aws_s3_bucket_public_access_block
```

Recommended defaults:

```text
Versioning: enabled
Encryption: AES256
Public access: blocked
```

---

### 2. IAM Policy

Create a least-privilege IAM policy for the POC.

Required actions:

```text
textract:StartDocumentAnalysis
textract:GetDocumentAnalysis
s3:GetObject
s3:PutObject
s3:ListBucket
```

Restrict S3 permissions to the POC bucket.

Textract permissions can remain resource-wide for this POC because these Textract document analysis actions commonly require `"Resource": "*"`.

---

### 3. Optional IAM User

For a simple local POC, Terraform can optionally create a dedicated IAM user:

```text
claims-textract-poc-user
```

Attach the POC IAM policy to that user.

Do not create long-lived access keys in Terraform unless this is a disposable sandbox, because the secret access key would be stored in Terraform state.

Preferred options:

1. Use an existing AWS CLI profile or AWS SSO profile.
2. Create only the policy in Terraform and attach it to an existing user or role.
3. Create a dedicated IAM user without access keys, then generate credentials outside Terraform if needed.

---

## Terraform Variables

Recommended variables:

```text
aws_region
project_name
bucket_name
create_iam_user
iam_user_name
```

Example defaults:

```text
project_name    = "claims-textract-poc"
create_iam_user = false
iam_user_name   = "claims-textract-poc-user"
```

If `bucket_name` is not provided, derive one using account ID and region:

```text
claims-textract-poc-<account-id>-<region>
```

---

## Terraform Outputs

Recommended outputs:

```text
bucket_name
input_example_s3_uri
output_example_s3_uri
iam_policy_arn
iam_user_name
run_command
```

Example run command output:

```text
python run_textract.py <bucket-name> raw/sample-claim.pdf
```

---

## Implementation Phases

### Phase 1: Create Terraform Skeleton

Create:

```text
infra/versions.tf
infra/variables.tf
infra/main.tf
infra/outputs.tf
infra/terraform.tfvars.example
```

Configure the AWS provider and required Terraform version.

---

### Phase 2: Add S3 Infrastructure

Add the POC bucket with:

```text
versioning
server-side encryption
public access blocking
basic tags
```

The bucket should support:

```text
raw/
output/
```

S3 folders do not need to be created explicitly. They are prefixes created when objects are uploaded.

---

### Phase 3: Add IAM Policy

Create an IAM policy that allows:

```text
Textract analysis calls
Read PDFs from the bucket
Write JSON output to the bucket
List the bucket
```

S3 object access should be scoped to:

```text
arn:aws:s3:::<bucket-name>/*
```

Bucket list access should be scoped to:

```text
arn:aws:s3:::<bucket-name>
```

---

### Phase 4: Add Optional IAM User

Use a boolean variable:

```text
create_iam_user
```

When `true`, create:

```text
aws_iam_user
aws_iam_user_policy_attachment
```

When `false`, only output the policy ARN.

---

### Phase 5: Run Terraform

From the `infra/` folder:

```bash
terraform init
terraform plan
terraform apply
```

---

### Phase 6: Upload a Sample PDF

Example:

```bash
aws s3 cp sample-claim.pdf s3://<bucket-name>/raw/sample-claim.pdf
```

---

### Phase 7: Run the Python POC

Example:

```bash
python run_textract.py <bucket-name> raw/sample-claim.pdf
```

Expected output:

```text
s3://<bucket-name>/output/sample-claim.json
```

---

### Phase 8: Verify JSON Output

Download the generated JSON:

```bash
aws s3 cp s3://<bucket-name>/output/sample-claim.json .
```

Inspect it:

```bash
cat sample-claim.json
```

---

## Recommended Version 1 Boundary

Keep version 1 focused on:

```text
Terraform-provisioned S3 bucket
Terraform-provisioned IAM policy
Local Python execution
Textract FORMS and TABLES
JSON output written back to S3
```

Do not convert to Lambda until the local script works reliably.

---

## Later Terraform Enhancements

After the simple POC works, add improvements in this order:

1. Lambda packaging and execution role
2. S3 event trigger for `raw/`
3. CloudWatch log group
4. Textract `QUERIES`
5. Step Functions orchestration
6. SNS or SQS for async job coordination
7. DynamoDB for job metadata
8. OpenSearch indexing
9. Bedrock cleanup or summarization
10. Human review workflow

