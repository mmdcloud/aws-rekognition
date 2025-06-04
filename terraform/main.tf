# Rekognition Role
module "rekognition_iam_role" {
  source             = "./modules/iam"
  role_name          = "rekognition_iam_role"
  role_description   = "rekognition_iam_role"
  policy_name        = "rekognition_iam_policy"
  policy_description = "rekognition_iam_policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": ""
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "rekognition.amazonaws.com"
                },
                "Effect": "Allow"
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
      "Effect" : "Allow"
      "Action" : [
        "rekognition:DetectLabels",
        "rekognition:DetectFaces",
        "rekognition:RecognizeCelebrities",
        "rekognition:DetectText",
        "rekognition:DetectModerationLabels"
      ]
      "Resource" : "*"
    },
    {
      "Effect" : "Allow"
      "Action" : [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      "Resource" : [
        aws_s3_bucket.rekognition_demo_bucket.arn,
        "${aws_s3_bucket.rekognition_demo_bucket.arn}/*"
      ]
    }
    EOF
}

# Lambda function Role
module "lambda_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "lambda_function_iam_role"
  role_description   = "lambda_function_iam_role"
  policy_name        = "lambda_function_iam_policy"
  policy_description = "lambda_function_iam_policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": ""
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow"
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "rekognition:*",
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents",
                  "s3:GetObject",
                  "s3:ListBucket"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            }
        ]
    }
    EOF
}

module "rekognition_processor" {
  source        = "./modules/lambda"
  function_name = "rekognition-image-processor"
  role_arn      = module.lambda_function_iam_role.arn
  permissions   = [
    {
      statement_id  = "AllowExecutionFromS3Bucket"
      action        = "lambda:InvokeFunction"
      function_name = aws_lambda_function.rekognition_processor.arn
      principal     = "s3.amazonaws.com"
      source_arn    = aws_s3_bucket.rekognition_demo_bucket.arn
    }
  ]
  env_variables = {
    BUCKET_NAME = aws_s3_bucket.rekognition_demo_bucket.bucket
  }
  handler                 = "index.handler"
  runtime                 = "python3.12"
  s3_bucket               = module.carshub_media_update_function_code.bucket
  s3_key                  = "lambda.zip"
}

module "rekognition_bucket" {
  source      = "./modules/s3"
  bucket_name = "rekognition-bucket-${random_id.bucket_suffix.hex}"
  objects = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["${module.carshub_media_cloudfront_distribution.domain_name}"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["${module.carshub_frontend_lb.lb_dns_name}"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = false
  bucket_notification = {
    queue = []
    lambda_function = [
      {
        lambda_function_arn = aws_lambda_function.rekognition_processor.arn
        events              = ["s3:ObjectCreated:*"]
        filter_prefix       = "images/"
      }
    ]
  }
}

# Create S3 bucket for storing images
resource "aws_s3_bucket" "rekognition_demo_bucket" {
  bucket = "rekognition-demo-bucket-${random_id.bucket_suffix.hex}"
  tags = {
    Name = "Rekognition Demo Bucket"
  }
}

# Lambda function for processing images
resource "aws_lambda_function" "rekognition_processor" {
  filename      = "./files/rekognition_processor.zip"
  function_name = "rekognition-image-processor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.rekognition_demo_bucket.bucket
    }
  }
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
