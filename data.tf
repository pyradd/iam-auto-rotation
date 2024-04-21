data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy" "AmazonSSMFullAccess" {
  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMFullAccess"
}

data "aws_iam_policy" "AmazonEC2FullAccess" {
  arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2FullAccess"
}
