import os
import requests
import yaml
from pprint import pprint

# Load environment variables
cloudflare_api_token = os.getenv('CLOUDFLARE_API_KEY')
godaddy_api_key = os.getenv('GODADDY_API_KEY')
godaddy_api_secret = os.getenv('GODADDY_API_SECRET')

# Ensure the necessary environment variables are set
if not cloudflare_api_token or not godaddy_api_key or not godaddy_api_secret:
    print("Error: CLOUDFLARE_API_KEY, GODADDY_API_KEY, and GODADDY_API_SECRET environment variables must be set.")
    exit(1)

# Read the list of domains from the YAML file
with open('../domains.yaml', 'r') as file:
    domains = yaml.safe_load(file).get('domains', [])

# Function to get Cloudflare nameservers for a domain
def get_cloudflare_nameservers(domain):
    url = 'https://api.cloudflare.com/client/v4/zones'
    headers = {
        'Authorization': f'Bearer {cloudflare_api_token}',
        'Content-Type': 'application/json',
    }
    params = {'name': domain}
    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()
    zones = response.json().get('result')
    if zones:
        zone_id = zones[0]['id']
        zone_details_url = f'https://api.cloudflare.com/client/v4/zones/{zone_id}'
        zone_response = requests.get(zone_details_url, headers=headers)
        zone_response.raise_for_status()
        zone_details = zone_response.json().get('result')
        return zone_details['name_servers']
    return None

# Function to update GoDaddy nameservers
def update_godaddy_nameservers(domain, nameservers):
    url = f'https://api.godaddy.com/v1/domains/{domain}/records/NS'
    headers = {
        'Authorization': f'sso-key {godaddy_api_key}:{godaddy_api_secret}',
        'Content-Type': 'application/json',
    }
    data = [{'data': ns, 'type': 'NS', 'name': '@'} for ns in nameservers]
    print(f"Requesting URL: {url}")
    print(f"Headers: {headers}")
    print(f"Payload: {data}")
    response = requests.put(url, headers=headers, json=data)
    try:
        response.raise_for_status()
        # Handle different types of responses
        if response.content:
            try:
                response_json = response.json()
                pprint(response_json)
            except ValueError:
                print(f"Response content: {response.content.decode()}")
        else:
            print("No content in response")
        return response
    except requests.exceptions.RequestException as e:
        print(f"Response status code: {response.status_code}")
        print(f"Response content: {response.content.decode()}")
        raise e

# Process each domain
for domain in domains:
    print(f"Processing {domain}...")
    try:
        cloudflare_nameservers = get_cloudflare_nameservers(domain)
        if cloudflare_nameservers:
            pprint(cloudflare_nameservers)
            update_response = update_godaddy_nameservers(domain, cloudflare_nameservers)
            print(f"Successfully updated nameservers for {domain}\n")
        else:
            print(f"Could not retrieve Cloudflare nameservers for {domain}\n")
    except requests.exceptions.RequestException as e:
        print(f"Error processing {domain}: {e}\n")
