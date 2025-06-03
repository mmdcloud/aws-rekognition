# Outputs
output "bucket_name" {
  value = aws_s3_bucket.rekognition_demo_bucket.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.rekognition_processor.function_name
}