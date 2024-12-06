from huggingface_hub import hf_hub_url, HfApi
import requests
import boto3
import os
import getopt, sys

def main(argv):
  model_name = None
  s3_bucket = None
  # Define short options "m:" and "b:" indicating both take arguments.
  # Define corresponding long options ["model-name=", "s3-bucket="] also indicating they take values.
  try:
      opts, _ = getopt.getopt(argv, "m:b:", ["model-name=", "s3-bucket="])
  except getopt.GetoptError:
      print("Usage: sync-model.py -m <model-name> -b <s3-bucket>")
      sys.exit(2)

  # Parse command line arguments
  for opt, arg in opts:
      if opt in ("-m", "--model-name"):
          model_name = arg
      elif opt in ("-b", "--s3-bucket"):
          s3_bucket = arg

  # Check if required arguments are provided
  if model_name is None or s3_bucket is None:
      print("Error: Both model name and S3 bucket must be specified.")
      print("Usage: sync-model.py -m <model-name> -b <s3-bucket>")
      sys.exit(2)

  # Print values to confirm they were captured correctly
  print("Model Name:", model_name)
  print("S3 Bucket:", s3_bucket)

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
  model_id    = model_name
  s3_prefix   = 'models/' + s3_bucket
  
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

if __name__ == "__main__":
    main(sys.argv[1:])
