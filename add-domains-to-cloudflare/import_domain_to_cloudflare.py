import os
import yaml
import requests
from pprint import pprint

# Load environment variables
cloudflare_email = os.getenv('CLOUDFLARE_EMAIL')
cloudflare_api_key = os.getenv('CLOUDFLARE_API_KEY')
cloudflare_account_id = os.getenv('CLOUDFLARE_ACCOUNT_ID')

# Ensure the necessary environment variables are set
if not cloudflare_email or not cloudflare_api_key or not cloudflare_account_id:
    print("Error: CLOUDFLARE_EMAIL, CLOUDFLARE_API_KEY, and CLOUDFLARE_ACCOUNT_ID environment variables must be set.")
    exit(1)

print(f"CLOUDFLARE_EMAIL: {cloudflare_email}")
print(f"CLOUDFLARE_API_KEY: {cloudflare_api_key}")
print(f"CLOUDFLARE_ACCOUNT_ID: {cloudflare_account_id}")

# Read the list of domains from the YAML file
with open('../domains.yaml', 'r') as file:
    domains = yaml.safe_load(file).get('domains', [])

# Add each domain to Cloudflare
for domain in domains:
    print(f"Adding {domain}:")

    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {cloudflare_api_key}',
    }

    data = {
        "account": {
            "id": cloudflare_account_id
        },
        "name": domain,
        "type": "full"
    }

    pprint(data)  # Print the data being sent for debugging

    try:
        response = requests.post('https://api.cloudflare.com/client/v4/zones', headers=headers, json=data)
        response.raise_for_status()  # This will raise an HTTPError if the HTTP request returned an unsuccessful status code

        response_data = response.json()
        pprint(response_data)  # Print the response data for debugging

        if response_data.get("success"):
            print(f"Successfully added {domain}\n")
        else:
            print(f"Failed to add {domain}: {response_data.get('errors')}\n")
    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}\n")