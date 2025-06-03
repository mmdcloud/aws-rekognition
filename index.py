import boto3
import json
import os

rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')

def handler(event, context):
    # Get the bucket and key from the S3 event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    print(f"Processing image: {key}")
    
    # Call Rekognition to detect labels
    response = rekognition.detect_labels(
        Image={
            'S3Object': {
                'Bucket': bucket,
                'Name': key
            }
        },
        MaxLabels=10,
        MinConfidence=70
    )
    
    # You can add other Rekognition features:
    # detect_faces_response = rekognition.detect_faces(...)
    # detect_text_response = rekognition.detect_text(...)
    # etc.
    
    # Store results in S3
    result_key = f"results/{key.split('/')[-1]}.json"
    s3.put_object(
        Bucket=bucket,
        Key=result_key,
        Body=json.dumps(response, indent=2)
    
    print(f"Results saved to: {result_key}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }