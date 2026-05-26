terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

locals {
  lambda_names = [
    "${var.project_name}-lambda-1",
    "${var.project_name}-lambda-2",
    "${var.project_name}-lambda-3",
    "${var.project_name}-lambda-4"
  ]
}
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_s3_bucket" "app" {
  bucket = "${var.project_name}-app-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "truststore" {
  bucket = "${var.project_name}-truststore-${data.aws_caller_identity.current.account_id}"
}
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "truststore" {
  bucket = aws_s3_bucket.truststore.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda.zip"
}
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "app" {
  for_each = toset(local.lambda_names)

  function_name = each.value
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tracing_config {
    mode = "Active"
  }
}
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = aws_lambda_function.app

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 14

  # kms_key_id = aws_kms_key.main.arn
}
   resource "aws_sqs_queue" "main" {
  name              = "${var.project_name}-queue"
  kms_master_key_id = aws_kms_key.main.arn
}

resource "aws_sns_topic" "main" {
  name              = "${var.project_name}-topic"
  kms_master_key_id = aws_kms_key.main.arn
}

resource "aws_cloudwatch_event_rule" "main" {
  name                = "${var.project_name}-event-rule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.main.name
  arn  = values(aws_lambda_function.app)[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = values(aws_lambda_function.app)[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.main.arn
}
 resource "aws_secretsmanager_secret" "main" {
  name       = "${var.project_name}-secret"
  kms_key_id = aws_kms_key.main.arn
}

resource "aws_secretsmanager_secret_version" "main" {
  secret_id = aws_secretsmanager_secret.main.id

  secret_string = jsonencode({
    username = "change-me"
    password = "change-me"
  })
}
  resource "aws_api_gateway_rest_api" "main" {
  name = "${var.project_name}-api"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "hello_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.hello.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.hello.id
  http_method             = aws_api_gateway_method.hello_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = values(aws_lambda_function.app)[0].invoke_arn
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = values(aws_lambda_function.app)[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
 resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello.id,
      aws_api_gateway_method.hello_get.id,
      aws_api_gateway_integration.lambda.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  xray_tracing_enabled = true
}
resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.useast1

  name  = "${var.project_name}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }
}
 resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = aws_s3_bucket.app.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
  resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "cloudfront.amazonaws.com"
        }

        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.app.arn}/*"

        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}
resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_shield_protection" "cloudfront" {
  count = var.enable_shield_advanced ? 1 : 0

  name         = "${var.project_name}-cloudfront-shield"
  resource_arn = aws_cloudfront_distribution.main.arn
}
resource "aws_iam_user" "learning_user" {
  name = "${var.project_name}-user"
}

resource "aws_iam_policy" "learning_policy" {
  name = "${var.project_name}-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "cloudwatch:GetMetricData"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "learning_user_policy" {
  user       = aws_iam_user.learning_user.name
  policy_arn = aws_iam_policy.learning_policy.arn
}
