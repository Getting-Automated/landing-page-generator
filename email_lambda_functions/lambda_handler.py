import json
import os
import boto3
from botocore.exceptions import ClientError

# Initialize the SES client
ses = boto3.client('ses', region_name='us-east-1')

def lambda_handler(event, context):
    # Handle preflight CORS request
    if event['requestContext']['http']['method'] == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',  # Adjust this for production
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps('OK')
        }
    
    # Parse the incoming JSON data
    body = json.loads(event['body'])
    site_id = body.get('siteId', 'Unknown Site')
    name = body.get('name', '')
    email = body.get('email', '')
    company = body.get('company', '')
    message = body.get('message', '')
    interests = ', '.join(body.get('interests', []))

    # Load HTML templates
    with open('owner_template.html', 'r') as file:
        owner_html_template = file.read()
    
    with open('submitter_template.html', 'r') as file:
        submitter_html_template = file.read()

    # Prepare email content
    SENDER = os.environ['SENDER_EMAIL']
    OWNER_RECIPIENT = os.environ['OWNER_EMAIL']
    
    # Format HTML content for owner
    owner_html_content = owner_html_template.format(
        siteId=site_id,
        name=name,
        email=email,
        message=message,
        company=company,
        interests=interests
    )
    
    submitter_html_content = submitter_html_template.format(
        name=name,
        interests=interests,
        message=message,
        site_id=site_id  # Add this line
    )

    try:
        # Send email to site owner
        ses.send_email(
            Destination={'ToAddresses': [OWNER_RECIPIENT]},
            Message={
                'Body': {
                    'Html': {'Data': owner_html_content},
                    'Text': {'Data': 'This is a HTML email. Please view in a HTML-capable email client.'}
                },
                'Subject': {'Data': f"New Contact Form Submission from {site_id}"},
            },
            Source=SENDER
        )

        # Send email to form submitter
        ses.send_email(
            Destination={'ToAddresses': [email]},
            Message={
                'Body': {
                    'Html': {'Data': submitter_html_content},
                    'Text': {'Data': 'This is a HTML email. Please view in a HTML-capable email client.'}
                },
                'Subject': {'Data': "Thank you for your inquiry"},
            },
            Source=SENDER
        )

        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',  # Adjust this for production
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'message': 'Form submitted successfully'})
        }
    except ClientError as e:
        print(e.response['Error']['Message'])
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',  # Adjust this for production
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'message': 'Error submitting form'})
        }