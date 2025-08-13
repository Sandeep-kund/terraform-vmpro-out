# S3 Bucket


resource "aws_s3_bucket" "source" {
  bucket = "demo-upload-bucket-sandeep-123456" # <-- make globally unique
}

# Optional hardening examples (uncomment as needed):
# resource "aws_s3_bucket_versioning" "source" {
#   bucket = aws_s3_bucket.source.id
#   versioning_configuration { status = "Enabled" }
# }
#
# resource "aws_s3_bucket_public_access_block" "source" {
#   bucket                  = aws_s3_bucket.source.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

############################
# IAM Role for Lambda


resource "aws_iam_role" "lambda_exec_role" {
  name = "s3_event_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "lambda.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Minimal permissions: logs + (optionally) read the uploaded object
resource "aws_iam_policy" "lambda_policy" {
  name        = "s3_event_lambda_policy"
  description = "Allow Lambda to read S3 object and write logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "S3ReadUploadedObject",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectAttributes"
        ],
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Sid    = "CloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

############################
# Lambda code (inline) -> file -> zip


locals {
  lambda_code = <<'PY'
import json
import urllib.parse
import boto3
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key    = urllib.parse.unquote_plus(record['s3']['object']['key'])

    print(f"New object uploaded -> bucket: {bucket}, key: {key}")

    # OPTIONAL: read the object content (demo)
    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        size = obj['ContentLength']
        content_type = obj.get('ContentType', 'unknown')
        print(f"Size: {size} bytes, Content-Type: {content_type}")
    except Exception as e:
        print("Could not read the object (ok for demo):", e)

    return {"ok": True, "bucket": bucket, "key": key}
PY
}

resource "local_file" "lambda_py" {
  filename = "${path.module}/lambda_function.py"
  content  = local.lambda_code
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_py.filename
  output_path = "${path.module}/lambda.zip"
}

############################
# Lambda Function


resource "aws_lambda_function" "s3_event_handler" {
  function_name = "s3_object_created_handler"
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filesha256(data.archive_file.lambda_zip.output_path)

  # Example: set a timeout if needed
  timeout = 30
}

############################
# Allow S3 to invoke Lambda


resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_event_handler.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}

############################
# S3 -> Lambda Notification


resource "aws_s3_bucket_notification" "s3_events" {
  bucket = aws_s3_bucket.source.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_event_handler.arn
    events              = ["s3:ObjectCreated:*"]
    # Optional filtering:
    # filter_prefix       = "inbox/"
    # filter_suffix       = ".txt"
  }

  # Ensure the permission exists before creating the notification,
  # otherwise you'll get "Unable to validate the following destination configurations"
  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

############################
# Useful outputs

output "bucket_name" {
  value = aws_s3_bucket.source.bucket
}

output "lambda_name" {
  value = aws_lambda_function.s3_event_handler.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.s3_event_handler.arn
}
