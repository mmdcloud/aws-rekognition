# Create S3 bucket for storing images
resource "aws_s3_bucket" "rekognition_demo_bucket" {
  bucket = "rekognition-demo-bucket-${random_id.bucket_suffix.hex}"
  tags = {
    Name = "Rekognition Demo Bucket"
  }
}

# Random suffix for bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# IAM role for Rekognition
resource "aws_iam_role" "rekognition_role" {
  name = "rekognition-demo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rekognition.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Rekognition
resource "aws_iam_policy" "rekognition_policy" {
  name        = "rekognition-demo-policy"
  description = "Policy for AWS Rekognition demo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectFaces",
          "rekognition:RecognizeCelebrities",
          "rekognition:DetectText",
          "rekognition:DetectModerationLabels"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.rekognition_demo_bucket.arn,
          "${aws_s3_bucket.rekognition_demo_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "rekognition_attach" {
  role       = aws_iam_role.rekognition_role.name
  policy_arn = aws_iam_policy.rekognition_policy.arn
}

# Lambda function for processing images
resource "aws_lambda_function" "rekognition_processor" {
  filename      = "rekognition_processor.zip"
  function_name = "rekognition-image-processor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "python3.8"
  timeout       = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.rekognition_demo_bucket.bucket
    }
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-rekognition-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda execution policy
resource "aws_iam_policy" "lambda_exec_policy" {
  name        = "lambda-rekognition-exec-policy"
  description = "Policy for Lambda to call Rekognition"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

# S3 event trigger for Lambda
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rekognition_processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.rekognition_demo_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.rekognition_demo_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.rekognition_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "images/"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}
