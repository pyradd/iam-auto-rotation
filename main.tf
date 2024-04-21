
resource "aws_s3_object" "object" {
  bucket = var.s3_bucket_name
  key    = "${var.s3_bucket_prefix}/template/${var.email_template_enforce}"
  source = "${path.module}/email-template/iam-auto-key-rotation-enforcement.html"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("${path.module}/email-template/iam-auto-key-rotation-enforcement.html")
}

##################################################################
# [ASA Notifier Module] Lambda Role & Function
##################################################################

data "archive_file" "notifier_lambda_function" {
  type = "zip"

  source_dir  = "${path.module}/notifier-lambda"                     # directory where your lambda funtion is located. path.module refers to terraform-iac/scheduled-lambda-deployment/lambda-function/ directory
  output_path = "${path.module}/notifier-lambda/notifier-lambda.zip" # where the zip file should be stored
}

resource "aws_iam_role" "notifier_function_execution_role" {
  name = "notifier-lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "managed_policy_1" {
  role       = aws_iam_role.notifier_function_execution_role.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}
resource "aws_iam_role_policy_attachment" "managed_policy_2" {
  role       = aws_iam_role.notifier_function_execution_role.name
  policy_arn = data.aws_iam_policy.AmazonSSMFullAccess.arn
}
resource "aws_iam_role_policy_attachment" "managed_policy_3" {
  role       = aws_iam_role.notifier_function_execution_role.name
  policy_arn = data.aws_iam_policy.AmazonEC2FullAccess.arn
}

data "aws_iam_policy_document" "notifier_lambda_function_attched_policy" {
  statement {
    sid       = "AllowFunctionAccessToEmailTemplates"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}/*"]
  }
  statement {
    sid       = "AllowFunctionToSendEmail"
    effect    = "Allow"
    actions   = ["ses:SendEmail"]
    resources = ["arn:${data.aws_partition.current.partition}:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/*"]
  }
}
resource "aws_iam_policy" "email_template_access" {
  name   = "AllowNotiferToGetEmailTemplate"
  policy = data.aws_iam_policy_document.notifier_lambda_function_attched_policy.json
}
resource "aws_iam_role_policy_attachment" "attach_notifier_funtion_policy" {
  role       = aws_iam_role.notifier_function_execution_role.name
  policy_arn = aws_iam_policy.email_template_access.arn
}

resource "aws_lambda_function" "notifier_lambda_function" {
  description      = "Function that received SNS events from config rules and emails end users who own the account id of the resource violation."
  function_name    = "ASA-Notifier"
  filename         = "${path.module}/notifier-lambda/notifier-lambda.zip"
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.notifier_lambda_function.output_base64sha256
  runtime          = "python3.10"
  role             = aws_iam_role.notifier_function_execution_role.arn
  timeout          = 300
  environment {
    variables = {
      ADMIN_EMAIL           = var.admin_email_address
      S3_BUCKET_NAME        = var.s3_bucket_name
      S3_BUCKET_PREFIX      = var.s3_bucket_prefix
      RunLambdaInVPC        = "False"
      SMTPUserParamName     = null # local.runInVPC ? var.smtp_user_param_name : null
      SMTPPasswordParamName = null # local.runInVPC ? var.smtp_password_param_name : null
    }
  }
}

##################################################################
# [AWS IAM Access Keys Rotation Module] Lambda Role & Function
##################################################################

data "archive_file" "access_key_rotate_lambda_function" {
  type = "zip"

  source_dir  = "${path.module}/access-key-rotate-lambda"                              # directory where your lambda funtion is located. path.module refers to terraform-iac/scheduled-lambda-deployment/lambda-function/ directory
  output_path = "${path.module}/access-key-rotate-lambda/access-key-rotate-lambda.zip" # where the zip file should be stored
}

resource "aws_iam_role" "rotation_lambda_function_execution_role" {
  name = var.execution_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "managed_policy_4" {
  role       = aws_iam_role.rotation_lambda_function_execution_role.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}

resource "aws_iam_role_policy_attachment" "managed_policy_5" {
  role       = aws_iam_role.rotation_lambda_function_execution_role.name
  policy_arn = data.aws_iam_policy.AmazonEC2FullAccess.arn
}

data "aws_iam_policy_document" "access_key_rotate_lambda_function_attched_policy" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.notifier_lambda_function.arn]
  }
  statement {
    sid    = "AllowSecretsManagerPermissions"
    effect = "Allow"
    actions = [
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:CreateSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ReplicateSecretToRegions"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:*"]
  }
  statement {
    sid    = "AllowIAMPolicyModification"
    effect = "Allow"
    actions = [
      "iam:List*",
      "iam:CreatePolicy",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "iam:PutUserPolicy",
      "iam:GetUserPolicy",
      "iam:GetAccessKeyLastUsed",
      "iam:GetUser"
    ]
    resources = ["*"]
  }
  statement {
    sid    = "AllowAttachUserPolicy"
    effect = "Allow"
    actions = [
      "iam:AttachUserPolicy"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:user/*"
    ]
  }
  statement {
    sid    = "AllowAttachSecretPolicy"
    effect = "Allow"
    actions = [
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:CreateSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ReplicateSecretToRegions"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:*"
    ]
  }
  statement {
    sid    = "AllowlistSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:ListSecrets"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "iam:GetGroup"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:group/${var.iam_exemption_group}"
    ]
  }

}
resource "aws_iam_policy" "rotation_function_access" {
  name   = "AllowRotationFunctionPermissions"
  policy = data.aws_iam_policy_document.access_key_rotate_lambda_function_attched_policy.json
}
resource "aws_iam_role_policy_attachment" "attach_rotation_function_policy" {
  role       = aws_iam_role.rotation_lambda_function_execution_role.name
  policy_arn = aws_iam_policy.rotation_function_access.arn
}

resource "aws_lambda_function" "access_key_rotate_lambda_function" {
  description      = "ASA Function to rotate IAM Access Keys on specified schedule"
  function_name    = "ASA-IAM-Access-Key-Rotation-Function"
  filename         = "${path.module}/access-key-rotate-lambda/access-key-rotate-lambda.zip"
  handler          = "main.lambda_handler"
  source_code_hash = data.archive_file.access_key_rotate_lambda_function.output_base64sha256
  runtime          = "python3.10"
  role             = aws_iam_role.rotation_lambda_function_execution_role.arn
  timeout          = 400
  environment {
    variables = {
      RecipientEmails              = jsonencode(var.recipient_emails)
      DryRunFlag                   = var.dry_run_flag
      RotationPeriod               = var.rotation_period
      InactivePeriod               = var.inactive_period
      InactiveBuffer               = var.inactive_buffer
      RecoveryGracePeriod          = var.recovery_grace_period
      IAMExemptionGroup            = var.iam_exemption_group
      IAMAssumedRoleName           = var.iam_role_name
      RoleSessionName              = "ASA-IAM-Access-Key-Rotation-Function"
      Partition                    = "${data.aws_partition.current.partition}"
      NotifierArn                  = aws_lambda_function.notifier_lambda_function.arn
      EmailTemplateEnforce         = var.email_template_enforce
      EmailTemplateAudit           = var.email_template_audit
      ResourceOwnerTag             = var.resource_owner_tag
      CredentialReplicationRegions = var.credential_replication_regions
      RunLambdaInVPC               = "False"
    }
  }
}

resource "aws_cloudwatch_event_rule" "rotation_cloud_watch_event_lambda_trigger" {
  name                = "IAM-Access-Key-Rotation-Event"
  description         = "CloudWatch Event to trigger Access Key auto-rotation Lambda Function daily"
  schedule_expression = "rate(24 hours)"
}

resource "aws_lambda_permission" "rotation_cloud_watch_event_lambda_trigger_lambda_permissions" {
  function_name = aws_lambda_function.access_key_rotate_lambda_function.arn
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rotation_cloud_watch_event_lambda_trigger.arn
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.rotation_cloud_watch_event_lambda_trigger.name
  target_id = "TriggerIAMRotaionLambda"
  arn       = aws_lambda_function.access_key_rotate_lambda_function.arn
}

resource "aws_iam_group" "asaiam_exemptions_group" {
  name = var.iam_exemption_group
}
