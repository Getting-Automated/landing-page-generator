import json
import os
import boto3
from botocore.exceptions import ClientError

# Initialize the SES client
ses = boto3.client('ses', region_name='us-east-1')

def lambda_handler(event, context):
    print("Lambda function invoked.")
    print(f"Event received: {json.dumps(event)}")

    # Define headers without CORS
    headers = {
        'Content-Type': 'application/json'
    }
    print(f"Headers set for response: {headers}")

    # Handle preflight OPTIONS request (no longer necessary as Function URL handles CORS)
    if event['requestContext']['http']['method'] == 'OPTIONS':
        print("Handling preflight OPTIONS request.")
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps('OK')
        }

    # Parse the incoming JSON data
    try:
        body = json.loads(event['body'])
        print(f"Parsed request body: {body}")
    except json.JSONDecodeError as e:
        print(f"JSONDecodeError: {str(e)}")
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Invalid JSON in request body'})
        }

    site_id = body.get('siteId', 'Unknown Site')
    name = body.get('name', '')
    email = body.get('email', '')
    company = body.get('company', '')
    message = body.get('message', '')
    interests = ', '.join(body.get('interests', []))
    print(f"Extracted Data - site_id: {site_id}, name: {name}, email: {email}, company: {company}, message: {message}, interests: {interests}")

    # Load HTML templates
    try:
        with open('owner_template.html', 'r') as file:
            owner_html_template = file.read()
        print("Loaded owner_template.html successfully.")
    except Exception as e:
        print(f"Error loading owner_template.html: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Server error loading templates'})
        }

    try:
        with open('submitter_template.html', 'r') as file:
            submitter_html_template = file.read()
        print("Loaded submitter_template.html successfully.")
    except Exception as e:
        print(f"Error loading submitter_template.html: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Server error loading templates'})
        }

    # Prepare email content
    SENDER = os.environ.get('SENDER_EMAIL', '')
    OWNER_RECIPIENT = os.environ.get('OWNER_EMAIL', '')
    print(f"SENDER_EMAIL: {SENDER}, OWNER_EMAIL: {OWNER_RECIPIENT}")

    if not SENDER or not OWNER_RECIPIENT:
        print("SENDER_EMAIL or OWNER_EMAIL environment variable is missing.")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Server configuration error'})
        }

    # Format HTML content for owner
    owner_html_content = owner_html_template.format(
        siteId=site_id,
        name=name,
        email=email,
        message=message,
        company=company,
        interests=interests
    )
    print("Formatted owner HTML content.")

    # Format HTML content for submitter
    submitter_html_content = submitter_html_template.format(
        name=name,
        interests=interests,
        message=message,
        site_id=site_id  # Add this line
    )
    print("Formatted submitter HTML content.")

    try:
        # Send email to site owner
        print(f"Sending email to site owner: {OWNER_RECIPIENT}")
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
        print("Email sent to site owner successfully.")

        # Send email to form submitter
        print(f"Sending confirmation email to submitter: {email}")
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
        print("Confirmation email sent to submitter successfully.")

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'status': 'success', 'message': 'Form submitted successfully'})
        }
    except ClientError as e:
        error_message = e.response['Error']['Message']
        print(f"ClientError when sending email: {error_message}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Error submitting form'})
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'status': 'error', 'message': 'Unexpected server error'})
        }