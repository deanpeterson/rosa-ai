from huggingface_hub import hf_hub_url, HfApi
import requests
import boto3
import os

# Initialize S3 client
s3 = boto3.client(
        's3', 
        endpoint_url=os.environ.get('ENDPOINT_URL'),
        aws_access_key_id=os.environ.get('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.environ.get('AWS_SECRET_ACCESS_KEY'),
        config=boto3.session.Config(signature_version='s3v4'),
        verify=False
)

# Model and S3 details
bucket_name = os.environ.get('AWS_S3_BUCKET')
model_id    = 'defog/llama-3-sqlcoder-8b'
s3_prefix   = 'models/llama-3-sqlcoder-8b/'

api = HfApi()
model_info = api.model_info(model_id)
requests.packages.urllib3.disable_warnings()

# Stream each file directly to S3
file_names = [f.rfilename for f in model_info.siblings]
for file_name in file_names:
    file_url = hf_hub_url(repo_id=model_id, filename=file_name)
    response = requests.get(file_url, stream=True)
    response.raise_for_status()
    
    s3_key = os.path.join(s3_prefix, file_name)
    s3.upload_fileobj(response.raw, bucket_name, s3_key)
    print(f"Uploaded {file_name} to {bucket_name}/{s3_key}")

