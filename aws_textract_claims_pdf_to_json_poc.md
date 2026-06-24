# Simple AWS Textract POC: Claims PDF to Structured JSON

## Goal

Build a simple proof of concept that:

```text
1. Takes a claims PDF already uploaded to S3
2. Passes the S3 bucket and key to AWS Textract
3. Extracts forms, key-value fields, lines, and tables
4. Maps the extracted data into a basic structured claims JSON
5. Saves the final JSON back to S3
```

For now, keep it simple.

Do not add these yet:

```text
Step Functions
SNS
SQS
DynamoDB
OpenSearch
Bedrock
Human review workflow
```

---

## Simple Architecture

```text
S3 PDF Upload
    |
    v
Python script / Lambda
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

---

## Example Input

Upload a claims PDF to S3:

```text
s3://claims-pdf-input/raw/sample-claim.pdf
```

Run the script with:

```bash
python run_textract.py claims-pdf-input raw/sample-claim.pdf
```

Expected output:

```text
s3://claims-pdf-input/output/sample-claim.json
```

---

## Folder Structure

```text
claims-textract-simple/
  README.md
  requirements.txt
  run_textract.py
  sample_output/
```

---

## requirements.txt

```text
boto3
```

Install dependencies:

```bash
pip install -r requirements.txt
```

---

## IAM Permissions Needed

For local AWS user, AWS profile, or Lambda role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "textract:StartDocumentAnalysis",
        "textract:GetDocumentAnalysis",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "*"
    }
  ]
}
```

For a real implementation, restrict S3 access to your specific bucket.

---

## Target JSON Format

The first version should generate a simple JSON like this:

```json
{
  "document": {
    "sourceBucket": "claims-pdf-input",
    "sourceKey": "raw/sample-claim.pdf"
  },
  "claim": {
    "claimId": "123456",
    "memberId": "M12345",
    "patientName": "John Smith",
    "providerName": "ABC Provider",
    "dateOfService": "01/15/2026",
    "totalBilledAmount": "$500.00",
    "totalPaidAmount": "$300.00",
    "serviceLines": [
      {
        "dateOfService": "01/15/2026",
        "procedureCode": "99213",
        "units": "1",
        "billedAmount": "$500.00",
        "allowedAmount": "$350.00",
        "paidAmount": "$300.00"
      }
    ]
  },
  "raw": {
    "keyValues": {},
    "tables": [],
    "lines": []
  }
}
```

---

## run_textract.py

```python
import boto3
import time
import json
import sys


textract = boto3.client("textract")
s3 = boto3.client("s3")


def start_textract_job(bucket, key):
    response = textract.start_document_analysis(
        DocumentLocation={
            "S3Object": {
                "Bucket": bucket,
                "Name": key
            }
        },
        FeatureTypes=["FORMS", "TABLES"]
    )

    return response["JobId"]


def wait_for_job(job_id):
    while True:
        response = textract.get_document_analysis(JobId=job_id)
        status = response["JobStatus"]

        print(f"Textract status: {status}")

        if status in ["SUCCEEDED", "FAILED"]:
            return status

        time.sleep(5)


def get_all_textract_results(job_id):
    blocks = []
    next_token = None

    while True:
        if next_token:
            response = textract.get_document_analysis(
                JobId=job_id,
                NextToken=next_token
            )
        else:
            response = textract.get_document_analysis(JobId=job_id)

        blocks.extend(response["Blocks"])

        next_token = response.get("NextToken")

        if not next_token:
            break

    return blocks


def get_text(block, block_map):
    text = []

    for relationship in block.get("Relationships", []):
        if relationship["Type"] == "CHILD":
            for child_id in relationship["Ids"]:
                child = block_map.get(child_id)

                if not child:
                    continue

                if child["BlockType"] == "WORD":
                    text.append(child.get("Text", ""))

                elif child["BlockType"] == "SELECTION_ELEMENT":
                    if child.get("SelectionStatus") == "SELECTED":
                        text.append("SELECTED")

    return " ".join(text).strip()


def extract_lines(blocks):
    lines = []

    for block in blocks:
        if block["BlockType"] == "LINE":
            lines.append({
                "text": block.get("Text", ""),
                "confidence": block.get("Confidence", 0)
            })

    return lines


def extract_key_values(blocks):
    block_map = {block["Id"]: block for block in blocks}

    key_map = {}
    value_map = {}

    for block in blocks:
        if block["BlockType"] == "KEY_VALUE_SET":
            entity_types = block.get("EntityTypes", [])

            if "KEY" in entity_types:
                key_map[block["Id"]] = block

            elif "VALUE" in entity_types:
                value_map[block["Id"]] = block

    key_values = {}

    for key_id, key_block in key_map.items():
        key_text = get_text(key_block, block_map)

        value_text = ""

        for relationship in key_block.get("Relationships", []):
            if relationship["Type"] == "VALUE":
                for value_id in relationship["Ids"]:
                    value_block = value_map.get(value_id)

                    if value_block:
                        value_text = get_text(value_block, block_map)

        if key_text:
            key_values[key_text] = value_text

    return key_values


def extract_tables(blocks):
    block_map = {block["Id"]: block for block in blocks}
    tables = []

    for block in blocks:
        if block["BlockType"] == "TABLE":
            table = {}

            for relationship in block.get("Relationships", []):
                if relationship["Type"] == "CHILD":
                    for child_id in relationship["Ids"]:
                        cell = block_map.get(child_id)

                        if not cell:
                            continue

                        if cell["BlockType"] == "CELL":
                            row_index = cell["RowIndex"]
                            col_index = cell["ColumnIndex"]
                            cell_text = get_text(cell, block_map)

                            table.setdefault(row_index, {})
                            table[row_index][col_index] = cell_text

            rows = []

            for row_index in sorted(table.keys()):
                row = []

                for col_index in sorted(table[row_index].keys()):
                    row.append(table[row_index][col_index])

                rows.append(row)

            tables.append(rows)

    return tables


def find_value(key_values, possible_keys):
    for search_key in possible_keys:
        for actual_key, value in key_values.items():
            if search_key.lower() in actual_key.lower():
                return value

    return None


def extract_service_lines_from_tables(tables):
    service_lines = []

    for table in tables:
        if not table:
            continue

        header = [h.lower() for h in table[0]]

        has_date_column = any("date" in h or "dos" in h for h in header)
        has_code_column = any(
            "code" in h or "cpt" in h or "procedure" in h or "hcpcs" in h
            for h in header
        )

        if not (has_date_column and has_code_column):
            continue

        for row in table[1:]:
            line = {}

            for index, header_name in enumerate(header):
                value = row[index] if index < len(row) else None

                if not value:
                    continue

                if "date" in header_name or "dos" in header_name:
                    line["dateOfService"] = value

                elif (
                    "cpt" in header_name
                    or "procedure" in header_name
                    or "hcpcs" in header_name
                    or "code" in header_name
                ):
                    line["procedureCode"] = value

                elif "unit" in header_name:
                    line["units"] = value

                elif "billed" in header_name or "charge" in header_name:
                    line["billedAmount"] = value

                elif "allowed" in header_name:
                    line["allowedAmount"] = value

                elif "paid" in header_name:
                    line["paidAmount"] = value

                elif "patient" in header_name and "responsibility" in header_name:
                    line["patientResponsibility"] = value

            if line:
                service_lines.append(line)

    return service_lines


def map_to_claim_json(bucket, key, lines, key_values, tables):
    claim_json = {
        "document": {
            "sourceBucket": bucket,
            "sourceKey": key
        },
        "claim": {
            "claimId": find_value(
                key_values,
                ["claim number", "claim id", "claim no", "claim"]
            ),
            "memberId": find_value(
                key_values,
                ["member id", "member number", "subscriber id", "patient account"]
            ),
            "patientName": find_value(
                key_values,
                ["patient name", "member name", "insured name"]
            ),
            "providerName": find_value(
                key_values,
                ["provider name", "billing provider", "rendering provider"]
            ),
            "dateOfService": find_value(
                key_values,
                ["date of service", "service date", "dos"]
            ),
            "totalBilledAmount": find_value(
                key_values,
                ["billed amount", "total charge", "charges", "amount billed"]
            ),
            "totalPaidAmount": find_value(
                key_values,
                ["paid amount", "payment amount", "amount paid"]
            ),
            "serviceLines": extract_service_lines_from_tables(tables)
        },
        "raw": {
            "keyValues": key_values,
            "tables": tables,
            "lines": lines
        }
    }

    return claim_json


def save_json_to_s3(bucket, output_key, data):
    s3.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=json.dumps(data, indent=2),
        ContentType="application/json"
    )


def build_output_key(input_key):
    if input_key.startswith("raw/"):
        output_key = input_key.replace("raw/", "output/", 1)
    else:
        output_key = f"output/{input_key}"

    if output_key.lower().endswith(".pdf"):
        output_key = output_key[:-4] + ".json"
    else:
        output_key = output_key + ".json"

    return output_key


def main():
    if len(sys.argv) != 3:
        print("Usage: python run_textract.py <bucket> <key>")
        print("Example: python run_textract.py claims-pdf-input raw/sample-claim.pdf")
        sys.exit(1)

    bucket = sys.argv[1]
    key = sys.argv[2]

    print("Starting Textract job...")
    job_id = start_textract_job(bucket, key)

    print(f"Textract JobId: {job_id}")

    status = wait_for_job(job_id)

    if status == "FAILED":
        raise Exception("Textract job failed")

    print("Fetching Textract results...")
    blocks = get_all_textract_results(job_id)

    print(f"Total blocks received: {len(blocks)}")

    print("Parsing lines...")
    lines = extract_lines(blocks)

    print("Parsing key-value fields...")
    key_values = extract_key_values(blocks)

    print("Parsing tables...")
    tables = extract_tables(blocks)

    print("Mapping to claims JSON...")
    claim_json = map_to_claim_json(
        bucket=bucket,
        key=key,
        lines=lines,
        key_values=key_values,
        tables=tables
    )

    output_key = build_output_key(key)

    print(f"Saving final JSON to s3://{bucket}/{output_key}")
    save_json_to_s3(bucket, output_key, claim_json)

    print("Done.")
    print(json.dumps(claim_json, indent=2))


if __name__ == "__main__":
    main()
```

---

## How to Run

### 1. Create project folder

```bash
mkdir claims-textract-simple
cd claims-textract-simple
```

### 2. Create files

Create:

```text
requirements.txt
run_textract.py
```

### 3. Install dependency

```bash
pip install -r requirements.txt
```

### 4. Upload PDF to S3

Example:

```bash
aws s3 cp sample-claim.pdf s3://claims-pdf-input/raw/sample-claim.pdf
```

### 5. Run Textract script

```bash
python run_textract.py claims-pdf-input raw/sample-claim.pdf
```

### 6. Check output JSON

```bash
aws s3 cp s3://claims-pdf-input/output/sample-claim.json .
cat sample-claim.json
```

---

## What This POC Does

This POC extracts:

```text
Lines
Key-value fields
Tables
Basic claim fields
Basic service lines
```

It creates:

```text
Structured claims JSON
Raw extracted data for debugging
```

---

## What This POC Does Not Do Yet

This version does not yet support:

```text
Advanced validation
Confidence scoring per claim field
Multi-format claim layouts
Human review
Step Functions orchestration
Automatic S3 trigger
Database persistence
OpenSearch indexing
Bedrock cleanup
```

---

## Important Notes

Textract does not directly return your final claims JSON.

Textract returns document blocks such as:

```text
LINE
WORD
KEY_VALUE_SET
TABLE
CELL
SELECTION_ELEMENT
```

Your parser converts those blocks into:

```text
keyValues
tables
lines
```

Then your mapper converts those into:

```text
claims JSON
```

Main POC focus:

```text
Textract Blocks -> Parser -> Structured Claims JSON
```

---

## Suggested Codex Prompt

Use this prompt in VS Code Codex:

```text
I am building a simple AWS Textract POC.

Goal:
- Input is a claims PDF already uploaded to S3.
- The script receives S3 bucket and key.
- It calls Textract StartDocumentAnalysis with FORMS and TABLES.
- It waits for the Textract job to complete.
- It fetches all Textract blocks using GetDocumentAnalysis pagination.
- It extracts lines, key-value pairs, and tables.
- It maps the extracted data into a basic structured claims JSON.
- It saves the final JSON back to S3 under output/.

Please review and improve run_textract.py.
Keep the implementation simple.
Do not add Step Functions, SNS, SQS, DynamoDB, OpenSearch, Bedrock, or Lambda yet.
Focus only on S3 -> Textract -> structured JSON -> S3.
```

---

## Next Improvements After This Works

After this basic POC works, improve in this order:

```text
1. Add Textract QUERIES for specific claim fields
2. Add confidence score for each extracted field
3. Improve service-line table detection
4. Add field normalization for dates and money values
5. Add validation rules
6. Convert script into Lambda
7. Add S3 trigger
8. Add Step Functions
```

---

## Version 2 Idea: Add Textract Queries

Later, update the Textract call like this:

```python
response = textract.start_document_analysis(
    DocumentLocation={
        "S3Object": {
            "Bucket": bucket,
            "Name": key
        }
    },
    FeatureTypes=["FORMS", "TABLES", "QUERIES"],
    QueriesConfig={
        "Queries": [
            {
                "Text": "What is the claim number?",
                "Alias": "claim_number"
            },
            {
                "Text": "What is the member ID?",
                "Alias": "member_id"
            },
            {
                "Text": "What is the patient name?",
                "Alias": "patient_name"
            },
            {
                "Text": "What is the provider name?",
                "Alias": "provider_name"
            },
            {
                "Text": "What is the total billed amount?",
                "Alias": "total_billed_amount"
            },
            {
                "Text": "What is the total paid amount?",
                "Alias": "total_paid_amount"
            }
        ]
    }
)
```

Do not add this in version 1 unless the basic FORMS and TABLES version is working.

---

## Resume Line After Completing POC

```text
Built a Python-based AWS Textract proof of concept to convert healthcare claims PDFs stored in S3 into structured JSON by extracting form fields, tables, service-line details, and claim metadata using Textract document analysis APIs.
```

