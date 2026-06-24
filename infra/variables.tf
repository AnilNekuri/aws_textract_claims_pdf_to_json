variable "aws_region" {
  description = "AWS region where the Textract POC resources will be created."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short name used for resource names and tags."
  type        = string
  default     = "claims-textract-poc"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-42 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name" {
  description = "Optional S3 bucket name. If empty, a name is derived from project name, AWS account ID, and region."
  type        = string
  default     = ""

  validation {
    condition = (
      var.bucket_name == "" ||
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    )
    error_message = "bucket_name must be empty or a valid lowercase S3 bucket name."
  }
}

variable "tags" {
  description = "Additional tags to apply to Terraform-managed resources."
  type        = map(string)
  default     = {}
}
