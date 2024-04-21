variable s3_bucket_name {
  description = "S3 Bucket Name where code is located, see the documentation for bucket names https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html"
  type = string
}
variable s3_bucket_prefix {
  description = "The prefix or directory where resources will be stored."
  type = string
  default = "asa-iam-rotation"
}
variable admin_email_address {
  description = "Email address that will be used in the 'sent from' section of the email. This needs to be a validated email identity in simple email service"
  type = string
}

variable "recipient_emails" {
  description = "List of recipient emails"
  type = list(string)
  validation {
    condition = length(var.recipient_emails) > 0 && can([for email in var.recipient_emails : regex("^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$", email)])
    error_message = "You need to provide valid and at least one recipient email"
  }
}

variable execution_role_name {
  description = "Enter the name of IAM Execution Role that will assume the sub-account role for Lambda Execution."
  type = string
  default = "asa-iam-key-rotation-lambda-execution-role"
}

variable dry_run_flag {
  description = "Enables/Disables key rotation functionality. 'True' only sends notifications to end users (Audit Mode). 'False' preforms key rotation and sends notifications to end users (Remediation Mode)."
  type = string
  default = "True"
}
variable rotation_period {
  description = "The number of days after which a key should be rotated (rotating from active to inactive)."
  type = string
  default = 90
}
variable inactive_period {
  description = "The number of days after which to inactivate keys that had been rotated (Note: This must be greater than RotationPeriod)."
  type = string
  default = 100
}
variable inactive_buffer {
  description = "The grace period between rotation and deactivation of a key."
  type = string
  default = 10
}
variable recovery_grace_period {
  description = "Recovery grace period between deactivation and deletion."
  type = string
  default = 10
}
variable iam_role_name {
  description = "Enter the name of IAM Role that the main ASA-iam-key-auto-rotation-and-notifier-solution.yaml CloudFormation template will assume."
  type = string
  default = "asa-iam-key-rotation-lambda-execution-role"
}
variable iam_exemption_group {
  description = "Manage IAM Key Rotation exemptions via an IAM Group. Enter the IAM Group name being used to facilitate IAM accounts excluded from auto-key rotation."
  type = string
  default = "IAMKeyRotationExemptionGroup"
}
variable email_template_enforce {
  description = "Enter the file name of the email html template to be sent out by the Notifier Module for Enforce Mode. Note: Must be located in the 'S3 Bucket Prefix/Template/template_name.html' folder"
  type = string
  default = "iam-auto-key-rotation-enforcement.html"
}
variable email_template_audit {
  description = "Enter the file name of the email html template to be sent out by the Notifier Module for Audit Mode. Note: Must be located in the 'S3 Bucket Prefix/Template/template_name.html' folder"
  type = string
  default = "iam-auto-key-rotation-enforcement.html"
}
variable resource_owner_tag {
  description = "(Optional) Tag key used to indicate the owner of an IAM user resource."
  type = string
  default = ""
}

variable credential_replication_regions {
  description = "Please provide the comma separated regions where you want to replicate the credentials (Secret Manager), e.g. us-east-2,us-west-1,us-west-2 Please skip the region where you are creating stack"
  type = string
  default = ""
}
