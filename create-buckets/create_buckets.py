import boto3
import yaml
import json
import logging

def read_config(file_path='bucket_names.yaml'):
    with open(file_path, 'r') as file:
        return yaml.safe_load(file)

def disable_block_public_access(bucket_name):
    s3_client = boto3.client('s3')
    s3_client.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            'BlockPublicAcls': False,
            'IgnorePublicAcls': False,
            'BlockPublicPolicy': False,
            'RestrictPublicBuckets': False
        }
    )
    logging.info(f"Public access block settings disabled for bucket {bucket_name}.")

def create_s3_bucket(bucket_name, region):
    s3_client = boto3.client('s3', region_name=region)
    
    try:
        # Create the S3 bucket
        if region == 'us-east-1':
            s3_client.create_bucket(Bucket=bucket_name)
        else:
            s3_client.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )
        logging.info(f"Bucket {bucket_name} created successfully.")
        
        # Disable block public access settings
        disable_block_public_access(bucket_name)
        
        # Enable public access
        public_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "PublicReadGetObject",
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "s3:GetObject",
                    "Resource": f"arn:aws:s3:::{bucket_name}/*"
                }
            ]
        }
        s3_client.put_bucket_policy(Bucket=bucket_name, Policy=json.dumps(public_policy))
        logging.info(f"Public access enabled for bucket {bucket_name}.")
        
        # Enable static website hosting
        website_configuration = {
            'ErrorDocument': {'Key': 'error.html'},
            'IndexDocument': {'Suffix': 'index.html'},
        }
        s3_client.put_bucket_website(
            Bucket=bucket_name,
            WebsiteConfiguration=website_configuration
        )
        logging.info(f"Static website hosting enabled for bucket {bucket_name}.")

        # Create a directory structure for subpages
        s3_resource = boto3.resource('s3')
        bucket = s3_resource.Bucket(bucket_name)
        
        subpages = ['subpage1/', 'subpage2/']
        for subpage in subpages:
            bucket.put_object(Key=(subpage + 'index.html'), Body='')
        logging.info(f"Directory structure created for bucket {bucket_name}.")

    except s3_client.exceptions.BucketAlreadyExists as e:
        logging.error(f"Bucket {bucket_name} already exists: {e}")
    except s3_client.exceptions.BucketAlreadyOwnedByYou as e:
        logging.error(f"Bucket {bucket_name} already owned by you: {e}")
    except s3_client.exceptions.ClientError as e:
        logging.error(f"Client error: {e}")
        if e.response['Error']['Code'] == 'AccessDenied':
            logging.error("Access denied. Please check your IAM permissions.")
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    config = read_config()
    for bucket in config['buckets']:
        create_s3_bucket(bucket['name'], bucket['region'])
        logging.info(f"Bucket {bucket['name']} created and configured for static website hosting.")
