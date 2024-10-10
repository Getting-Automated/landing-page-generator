#!/bin/bash

set -euo pipefail

# Set up logging
LOG_FILE="deploy.log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error flags
S3_BUCKET_CREATED=false
CLOUDFRONT_DISTRIBUTION_CREATED=false
CERTIFICATE_CREATED=false
ROUTE53_RECORDS_CREATED=false

# Function to print formatted messages
print_message() {
    local type=$1
    local message=$2
    case $type in
        "info")
            echo -e "${BLUE}ℹ️ INFO:${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}✅ SUCCESS:${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️ WARNING:${NC} $message"
            ;;
        "error")
            echo -e "${RED}❌ ERROR:${NC} $message"
            ;;
    esac
}


# Rollback function
rollback() {
    print_message "warning" "Deployment failed. Rolling back changes..."
    
    # Rollback S3 bucket
    if [ "${S3_BUCKET_CREATED:-false}" = true ]; then
        print_message "info" "Deleting newly created S3 bucket: $S3_BUCKET"
        aws s3 rb s3://$S3_BUCKET --force --profile $AWS_CLI_PROFILE
    fi
    
    # Rollback CloudFront distribution
    if [ -n "${CLOUDFRONT_DISTRIBUTION_CREATED:-}" ]; then
        print_message "info" "Deleting newly created CloudFront distribution: $CLOUDFRONT_DISTRIBUTION_ID"
        aws cloudfront delete-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --if-match $(aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query 'ETag' --output text --profile $AWS_CLI_PROFILE) --profile $AWS_CLI_PROFILE
    fi
    
    # Rollback SSL certificate
    if [ -n "${CERTIFICATE_CREATED:-}" ]; then
        print_message "info" "Deleting newly created SSL certificate: $CERTIFICATE_ARN"
        aws acm delete-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --profile $AWS_CLI_PROFILE
    fi
    
    # Rollback Route 53 records
    if [ -n "${ROUTE53_RECORDS_CREATED:-}" ]; then
        print_message "info" "Deleting newly created Route 53 records"
        # You would need to implement the logic to delete specific records here
    fi
    
    print_message "info" "Rollback completed."
    exit 1
}

# Trap for error handling
trap 'rollback' ERR



# Function to show a spinner while a command is running
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Load configuration
CONFIG_FILE="deploy-config.env"
if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value
    do
        # Ignore comments and empty lines
        if [[ ! $key =~ ^# && -n $key ]]; then
            # Remove any leading/trailing whitespace and quotes from the value
            value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
            export "$key=$value"
        fi
    done < "$CONFIG_FILE"
else
    print_message "error" "Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Validate environment variables and set S3_BUCKET
validate_env_variables() {
    required_vars=("AWS_REGION" "AWS_CLI_PROFILE" "DOMAIN_NAME" "DNS_METHOD")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_message "error" "Required environment variable $var is not set."
            exit 1
        fi
    done
    # Set S3_BUCKET to DOMAIN_NAME
    S3_BUCKET=$DOMAIN_NAME
    export S3_BUCKET
}

# Validate environment variables and set S3_BUCKET
validate_env_variables

# Function to validate AWS configuration
validate_aws_config() {
    print_message "info" "Validating AWS configuration..."

    # Validate AWS region
    if ! aws ec2 describe-regions --region $AWS_REGION --query "Regions[?RegionName=='$AWS_REGION'].RegionName" --output text --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "Invalid AWS region: $AWS_REGION"
        exit 1
    fi

    # Validate AWS CLI profile
    if ! aws sts get-caller-identity --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "Invalid or unconfigured AWS CLI profile: $AWS_CLI_PROFILE"
        exit 1
    fi

    print_message "success" "AWS configuration is valid."
}

# Function to check AWS CLI configuration
check_aws_cli_config() {
    if ! aws sts get-caller-identity --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "AWS CLI is not configured correctly or the profile '$AWS_CLI_PROFILE' doesn't exist."
        exit 1
    fi
}

# Function to validate S3 bucket name
validate_bucket_name() {
    local bucket_name="$1"
    
    # Check if bucket name is empty
    if [ -z "$bucket_name" ]; then
        print_message "error" "S3 bucket name is empty."
        return 1
    fi
    
    # Check length (3-63 characters)
    if [ ${#bucket_name} -lt 3 ] || [ ${#bucket_name} -gt 63 ]; then
        print_message "error" "S3 bucket name must be between 3 and 63 characters long."
        return 1
    fi
    
    # Check if it's a valid domain name format
    if ! echo "$bucket_name" | grep -qE '^[a-z0-9][a-z0-9.-]*[a-z0-9]$'; then
        print_message "error" "S3 bucket name must be in valid domain name format."
        print_message "info" "It should contain only lowercase letters, numbers, hyphens, and periods."
        print_message "info" "It must start and end with a letter or number."
        return 1
    fi
    
    # Check for consecutive periods
    if echo "$bucket_name" | grep -q '\.\.'; then
        print_message "error" "S3 bucket name cannot contain consecutive periods."
        return 1
    fi
    
    # Check if it's not an IP address
    if echo "$bucket_name" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        print_message "error" "S3 bucket name cannot be formatted as an IP address."
        return 1
    fi
    
    return 0
}

# Function to install AWS CLI
install_aws_cli() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_message "info" "Attempting to install AWS CLI on Linux..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        print_message "info" "Attempting to install AWS CLI on macOS..."
        curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
        sudo installer -pkg AWSCLIV2.pkg -target /
        rm AWSCLIV2.pkg
    else
        print_message "error" "Unsupported operating system for automatic AWS CLI installation."
        exit 1
    fi
}

# Function to check S3 permissions
check_s3_permissions() {
    if ! aws s3 ls s3://$S3_BUCKET --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "Unable to access S3 bucket. Check your permissions."
        exit 1
    fi
}

# Function to build React app
build_react_app() {
    # Store the current directory
    SCRIPT_DIR="$(pwd)"

    # Navigate to the parent directory where the React app is located
    cd ..

    # Build the React app
    print_message "info" "Building the React app..."
    if npm run build; then
        print_message "success" "React app built successfully."
    else
        print_message "error" "Failed to build React app. Check your application code and build configuration."
        cd "$SCRIPT_DIR"  # Return to the original directory
        exit 1
    fi

    # Check if build directory exists
    if [ ! -d "build" ]; then
        print_message "error" "Build directory 'build/' does not exist. The build process may have failed."
        cd "$SCRIPT_DIR"  # Return to the original directory
        exit 1
    fi

    # Sync build folder with S3 bucket
    print_message "info" "Uploading to S3 bucket..."
    if aws s3 sync build/ s3://$S3_BUCKET --delete --profile $AWS_CLI_PROFILE; then
        print_message "success" "Successfully uploaded build to S3 bucket."
    else
        print_message "error" "Failed to upload build to S3 bucket. Check your AWS permissions and S3 bucket configuration."
        cd "$SCRIPT_DIR"  # Return to the original directory
        exit 1
    fi

    # Return to the original directory
    cd "$SCRIPT_DIR"
}

# Function to validate CloudFront distribution
validate_cloudfront_distribution() {
    if ! aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "Unable to access CloudFront distribution. Check your permissions and distribution ID."
        exit 1
    fi
}

# Function to validate SSL certificate
validate_ssl_certificate() {
    print_message "info" "Validating existing SSL certificate..."
    
    # Get all certificates for the domain
    CERT_ARNS=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE)
    
    if [ -z "$CERT_ARNS" ]; then
        print_message "warning" "No certificates found for $DOMAIN_NAME"
        return 1
    fi
    
    for CERT_ARN in $CERT_ARNS; do
        print_message "info" "Checking certificate: $CERT_ARN"
        
        # Get the domains the certificate is valid for
        CERT_DOMAINS=$(aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query 'Certificate.DomainValidationOptions[].DomainName' --output text --profile $AWS_CLI_PROFILE)
        
        # Check if the intended domain is in the list of valid domains
        if echo "$CERT_DOMAINS" | grep -q "$DOMAIN_NAME"; then
            # Check certificate status
            CERT_STATUS=$(aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query 'Certificate.Status' --output text --profile $AWS_CLI_PROFILE)
            
            if [ "$CERT_STATUS" = "ISSUED" ]; then
                print_message "success" "Valid certificate found for $DOMAIN_NAME. ARN: $CERT_ARN"
                export CERTIFICATE_ARN=$CERT_ARN
                return 0
            else
                print_message "warning" "Certificate found but status is $CERT_STATUS. ARN: $CERT_ARN"
                print_message "info" "Please follow these steps:"
                print_message "info" "1. Check the AWS ACM console for more details on the certificate status"
                print_message "info" "2. Ensure that the DNS validation records are correctly set up"
                print_message "info" "3. If using Route 53, verify that the hosted zone is correctly configured"
                print_message "info" "4. Check that your domain's nameservers are correctly set at your registrar"
                print_message "info" "5. Wait for the DNS changes to propagate (this can take up to 48 hours)"
                print_message "info" "6. Once the certificate status changes to 'Issued', run this script again"
                echo
                print_message "info" "If you continue to have issues or the status is different:"
                print_message "info" "  - Check the AWS ACM troubleshooting guide: https://docs.aws.amazon.com/acm/latest/userguide/troubleshooting.html"
                print_message "info" "  - Verify that you have the necessary permissions to validate the certificate"
                echo
                print_message "info" "If you need to request a new certificate:"
                print_message "info" "  1. Delete the current certificate in ACM"
                print_message "info" "  2. Remove the CERTIFICATE_ARN from your deploy-config.env file"
                print_message "info" "  3. Run this script again to request a new certificate"
                return 1
            fi
        else
            print_message "warning" "Certificate does not support $DOMAIN_NAME. ARN: $CERT_ARN"
        fi
    done
    
    print_message "error" "No valid certificate found for $DOMAIN_NAME"
    print_message "info" "Available certificates and their domains:"
    for CERT_ARN in $CERT_ARNS; do
        CERT_DOMAINS=$(aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query 'Certificate.DomainValidationOptions[].DomainName' --output text --profile $AWS_CLI_PROFILE)
        echo "  ARN: $CERT_ARN"
        echo "  Domains: $CERT_DOMAINS"
        echo
    done
    
    print_message "info" "A new certificate needs to be requested for $DOMAIN_NAME"
    return 1
}

# Function to check Route 53 hosted zone
check_route53_hosted_zone() {
    if ! aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --profile $AWS_CLI_PROFILE &>/dev/null; then
        print_message "error" "Unable to access Route 53 hosted zone. Check your permissions and hosted zone ID."
        exit 1
    fi
}

# Function to check DNS propagation
check_dns_propagation() {
    print_message "info" "Checking DNS configuration for $DOMAIN_NAME..."
    
    # Ensure we have the CloudFront domain
    if [ -z "$CLOUDFRONT_DOMAIN" ]; then
        get_cloudfront_domain
    fi
    
    # Method 1: Using dig
    dig_result=$(dig +short $DOMAIN_NAME) || {
        print_message "error" "Error checking DNS with dig"
        return 1
    }

    # Method 2: Using host
    host_result=$(host $DOMAIN_NAME) || {
        print_message "error" "Error checking DNS with host"
        return 1
    }

    # Method 3: Using nslookup
    nslookup_result=$(nslookup $DOMAIN_NAME | grep 'Address:' | tail -n1) || {
        print_message "error" "Error checking DNS with nslookup"
        return 1
    }

    # Check results
    if echo "$dig_result" | grep -q "$CLOUDFRONT_DOMAIN"; then
        print_message "success" "DNS is correctly configured. $DOMAIN_NAME is pointing to the CloudFront distribution (verified with dig)."
        return 0
    elif echo "$host_result" | grep -q "$CLOUDFRONT_DOMAIN"; then
        print_message "success" "DNS is correctly configured. $DOMAIN_NAME is pointing to the CloudFront distribution (verified with host)."
        return 0
    elif echo "$nslookup_result" | grep -q "$CLOUDFRONT_DOMAIN"; then
        print_message "success" "DNS is correctly configured. $DOMAIN_NAME is pointing to the CloudFront distribution (verified with nslookup)."
        return 0
    else
        print_message "info" "DNS is not yet configured to point to the CloudFront distribution."
        print_message "info" "dig result: $dig_result"
        print_message "info" "host result: $host_result"
        print_message "info" "nslookup result: $nslookup_result"
        return 1
    fi
}

# Function to request and validate certificate
request_and_validate_certificate() {
    print_message "info" "Checking for existing SSL certificate..."
    CERT_ARN=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE)

    if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" = "None" ]; then
        print_message "info" "Requesting new SSL certificate..."
        CERT_ARN=$(aws acm request-certificate --domain-name "$DOMAIN_NAME" --validation-method DNS --subject-alternative-names "www.$DOMAIN_NAME" --region us-east-1 --query "CertificateArn" --output text --profile $AWS_CLI_PROFILE)
        
        print_message "success" "Certificate requested. ARN: $CERT_ARN"
        print_message "info" "Waiting for ACM to generate DNS validation records..."
        sleep 30  # Wait for ACM to generate the DNS records
        
        # Get the DNS validation records
        DNS_VALIDATION_RECORDS=$(aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query "Certificate.DomainValidationOptions[].ResourceRecord" --output json --profile $AWS_CLI_PROFILE)
        
        # Create the validation records in Route 53
        for record in $(echo $DNS_VALIDATION_RECORDS | jq -c '.[]'); do
            NAME=$(echo $record | jq -r '.Name')
            VALUE=$(echo $record | jq -r '.Value')
            
            aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch "{
                \"Changes\": [{
                    \"Action\": \"UPSERT\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$NAME\",
                        \"Type\": \"CNAME\",
                        \"TTL\": 300,
                        \"ResourceRecords\": [{\"Value\": \"$VALUE\"}]
                    }
                }]
            }" --profile $AWS_CLI_PROFILE
        done
        
        print_message "success" "DNS validation records created. Certificate validation in progress..."
        print_message "info" "This may take several minutes. Please wait..."
        
        # Wait for certificate validation
        aws acm wait certificate-validated --certificate-arn $CERT_ARN
        
        if [ $? -eq 0 ]; then
            print_message "success" "Certificate validated successfully."
        else
            print_message "error" "Certificate validation failed or timed out. Please check the AWS ACM console for more information."
            exit 1
        fi
    else
        print_message "info" "Existing certificate found. ARN: $CERT_ARN"
    fi
    
    # Update .env file with the certificate ARN
    sed -i.bak "s/CERTIFICATE_ARN=.*/CERTIFICATE_ARN=$CERT_ARN/" $CONFIG_FILE && rm ${CONFIG_FILE}.bak
    export CERTIFICATE_ARN=$CERT_ARN
}

# Function to create or get CloudFront distribution
create_or_get_cloudfront_distribution() {
    print_message "info" "Checking for existing CloudFront distribution..."
    EXISTING_DIST=$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[?contains(@, '$DOMAIN_NAME')]].Id" --output text --profile $AWS_CLI_PROFILE)

    if [ -z "$EXISTING_DIST" ]; then
        print_message "info" "Creating new CloudFront distribution..."
        
        # Get the certificate ARN
        CERTIFICATE_ARN=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE)
        
        if [ -z "$CERTIFICATE_ARN" ]; then
            print_message "error" "No certificate found for $DOMAIN_NAME. Please ensure the certificate exists in ACM."
            exit 1
        fi

        # Create a JSON file for the CloudFront distribution configuration
        cat << EOF > /tmp/cloudfront-config.json
{
    "CallerReference": "$(date +%s)",
    "Aliases": {
        "Quantity": 2,
        "Items": ["$DOMAIN_NAME", "www.$DOMAIN_NAME"]
    },
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-Website",
                "DomainName": "$S3_BUCKET.s3-website-$AWS_REGION.amazonaws.com",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only"
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-Website",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 300,
        "MaxTTL": 1200,
        "Compress": true
    },
    "Comment": "Distribution for $DOMAIN_NAME",
    "Enabled": true,
    "ViewerCertificate": {
        "ACMCertificateArn": "$CERTIFICATE_ARN",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    }
}
EOF

        # Create the CloudFront distribution
        CLOUDFRONT_DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config file:///tmp/cloudfront-config.json --query "Distribution.Id" --output text --profile $AWS_CLI_PROFILE)
        
        if [ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
            print_message "error" "Failed to create CloudFront distribution."
            exit 1
        fi

        print_message "success" "CloudFront distribution created. ID: $CLOUDFRONT_DISTRIBUTION_ID"
        
        # Clean up
        rm /tmp/cloudfront-config.json
    else
        CLOUDFRONT_DISTRIBUTION_ID=$EXISTING_DIST
        print_message "info" "Using existing CloudFront distribution. ID: $CLOUDFRONT_DISTRIBUTION_ID"
    fi

    # Update .env file with the CloudFront distribution ID
    sed -i.bak "s/CLOUDFRONT_DISTRIBUTION_ID=.*/CLOUDFRONT_DISTRIBUTION_ID=$CLOUDFRONT_DISTRIBUTION_ID/" $CONFIG_FILE && rm ${CONFIG_FILE}.bak
    export CLOUDFRONT_DISTRIBUTION_ID=$CLOUDFRONT_DISTRIBUTION_ID
}

# Function to create or get Route 53 hosted zone and check nameservers
create_or_get_hosted_zone_and_check_nameservers() {
    print_message "info" "Checking for existing Route 53 hosted zone..."
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --query "HostedZones[0].Id" --output text --profile $AWS_CLI_PROFILE)
    
    if [ "$HOSTED_ZONE_ID" = "None" ] || [ -z "$HOSTED_ZONE_ID" ]; then
        print_message "info" "Creating new Route 53 hosted zone for $DOMAIN_NAME..."
        HOSTED_ZONE_ID=$(aws route53 create-hosted-zone --name "$DOMAIN_NAME" --caller-reference "$(date +%s)" --query "HostedZone.Id" --output text --profile $AWS_CLI_PROFILE)
        print_message "success" "New hosted zone created with ID: $HOSTED_ZONE_ID"
    else
        print_message "info" "Existing hosted zone found with ID: $HOSTED_ZONE_ID"
    fi

    # Get Route 53 nameservers
    R53_NAMESERVERS=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" --query "DelegationSet.NameServers" --output text --profile $AWS_CLI_PROFILE)

    # Get current nameservers from the domain registrar
    CURRENT_NAMESERVERS=$(dig +short NS $DOMAIN_NAME)

    # Compare nameservers
    if [ "$R53_NAMESERVERS" = "$CURRENT_NAMESERVERS" ]; then
        print_message "success" "Nameservers are correctly set to Route 53."
    else
        print_message "warning" "Nameservers are not correctly set to Route 53."
        print_message "warning" "Please update your domain's nameservers at your registrar to the following:"
        echo "$R53_NAMESERVERS"
        print_message "warning" "Current nameservers are:"
        echo "$CURRENT_NAMESERVERS"
        print_message "warning" "DNS updates will not take effect until nameservers are updated."
    fi
}

# Function to update DNS using Route 53
update_route53_dns() {
    print_message "info" "Updating DNS records using Route 53..."
    
    # Get the CloudFront domain name
    CF_DOMAIN=$(aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE)
    
    if [ -z "$CF_DOMAIN" ]; then
        print_message "error" "Could not retrieve CloudFront domain name."
        return 1
    fi
    
    # Create a JSON file for the Route 53 change batch
    cat << EOF > /tmp/route53-change-batch.json
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME}",
                "Type": "A",
                "AliasTarget": {
                    "HostedZoneId": "Z2FDTNDATAQYW2",
                    "DNSName": "${CF_DOMAIN}",
                    "EvaluateTargetHealth": false
                }
            }
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "www.${DOMAIN_NAME}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${CF_DOMAIN}"
                    }
                ]
            }
        }
    ]
}
EOF
    
    # Update the Route 53 record
    aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///tmp/route53-change-batch.json --profile $AWS_CLI_PROFILE
    
    if [ $? -eq 0 ]; then
        print_message "success" "DNS updated successfully. It may take some time for changes to propagate."
    else
        print_message "error" "Error updating DNS. Please check your AWS credentials and Route 53 configuration."
    fi
    
    # Clean up
    rm /tmp/route53-change-batch.json
}

# Function to provide manual DNS update information
provide_manual_dns_info() {
    print_message "info" "Retrieving CloudFront and Certificate information..."
    
    # Get the CloudFront domain name
    CF_DOMAIN=$(aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE)
    
    if [ -z "$CF_DOMAIN" ]; then
        print_message "error" "Could not retrieve CloudFront domain name."
        return 1
    fi
    
    print_message "info" "To point your domain to this website and validate your SSL certificate, create the following DNS records at your DNS provider:"
    echo
    echo "1. For the root domain (${DOMAIN_NAME}):"
    echo "   Option A (if your DNS provider supports ALIAS records for A records):"
    echo "     Type: A"
    echo "     Name: @"
    echo "     Value: Set up an ALIAS record pointing to ${CF_DOMAIN}"
    echo
    echo "   Option B (if your DNS provider doesn't support ALIAS for A records):"
    echo "     Type: CNAME"
    echo "     Name: www"
    echo "     Value: ${CF_DOMAIN}"
    echo "     Then, set up a URL redirect from the root domain to www.${DOMAIN_NAME}"
    echo
    echo "2. For the www subdomain (www.${DOMAIN_NAME}):"
    echo "   Type: CNAME"
    echo "   Name: www"
    echo "   Value: ${CF_DOMAIN}"
    echo
    
    # Only show SSL certificate validation records if a new certificate was created
    if [ "${CERTIFICATE_CREATED:-false}" = true ]; then
        # Get certificate validation records
        CERT_VALIDATION_RECORDS=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query "Certificate.DomainValidationOptions[].ResourceRecord" --output json --profile $AWS_CLI_PROFILE)
        
        echo "3. For SSL certificate validation:"
        echo "$CERT_VALIDATION_RECORDS" | jq -r '.[] | "   Type: \(.Type)\n   Name: \(.Name)\n   Value: \(.Value)\n"'
    fi
    
    print_message "warning" "Please update your DNS records as instructed above."
    print_message "info" "If your DNS provider doesn't support ALIAS records for the root domain:"
    print_message "info" "1. Set up the CNAME for 'www' as shown in Option B."
    print_message "info" "2. Configure a URL redirect from ${DOMAIN_NAME} to www.${DOMAIN_NAME}"
    print_message "info" "3. This ensures both the root domain and www subdomain work correctly."
    echo
    print_message "info" "After updating, it may take up to 48 hours for DNS changes to propagate fully."
    if [ "${CERTIFICATE_CREATED:-false}" = true ]; then
        print_message "info" "Certificate validation may take several minutes to a few hours after the DNS records are updated."
    fi
    print_message "info" "Once the changes have propagated, run this script again to complete the deployment."
}

# Function to create S3 bucket and configure it for static website hosting
create_and_configure_s3_bucket() {
    print_message "info" "Checking if S3 bucket exists..."
    if aws s3 ls "s3://$S3_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        print_message "info" "S3 bucket does not exist. Creating bucket $S3_BUCKET..."
        if ! OUTPUT=$(aws s3 mb s3://$S3_BUCKET --region $AWS_REGION --profile $AWS_CLI_PROFILE 2>&1); then
            print_message "error" "Failed to create S3 bucket: $OUTPUT"
            exit 1
        fi
        print_message "success" "S3 bucket created successfully."
    else
        print_message "info" "S3 bucket already exists."
    fi

    print_message "info" "Configuring bucket for static website hosting..."
    if ! OUTPUT=$(aws s3 website s3://$S3_BUCKET --index-document index.html --error-document index.html --profile $AWS_CLI_PROFILE 2>&1); then
        print_message "error" "Failed to configure S3 bucket for static website hosting: $OUTPUT"
        exit 1
    fi

    print_message "info" "Setting bucket policy for public read access..."
    BUCKET_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'"$S3_BUCKET"'/*"
            }
        ]
    }'
    
    if ! OUTPUT=$(echo "$BUCKET_POLICY" | aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file:///dev/stdin --profile $AWS_CLI_PROFILE 2>&1); then
        print_message "error" "Failed to set bucket policy: $OUTPUT"
        exit 1
    fi

    # Verify the website configuration
    if ! OUTPUT=$(aws s3api get-bucket-website --bucket $S3_BUCKET --profile $AWS_CLI_PROFILE 2>&1); then
        print_message "error" "Failed to verify bucket website configuration: $OUTPUT"
        exit 1
    fi

    print_message "success" "S3 bucket configured successfully for static website hosting."
}

# Function to check if resources already exist
check_existing_resources() {
    print_message "info" "Checking existing resources..."
    
    # Check S3 bucket
    if aws s3 ls "s3://$S3_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        S3_EXISTS=false
    else
        S3_EXISTS=true
        print_message "info" "S3 bucket already exists: $S3_BUCKET"
    fi
    
    # Check CloudFront distribution
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0] == '${DOMAIN_NAME}'].Id" --output text --profile $AWS_CLI_PROFILE)
    if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
        CF_EXISTS=false
    else
        CF_EXISTS=true
        print_message "info" "CloudFront distribution already exists: $DISTRIBUTION_ID"
    fi
    
    # Check Route 53 hosted zone
    if [ "$DNS_METHOD" = "route53" ]; then
        HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --query "HostedZones[0].Id" --output text --profile $AWS_CLI_PROFILE)
        if [ "$HOSTED_ZONE_ID" = "None" ] || [ -z "$HOSTED_ZONE_ID" ]; then
            R53_EXISTS=false
        else
            R53_EXISTS=true
            print_message "info" "Route 53 hosted zone already exists: $HOSTED_ZONE_ID"
        fi
    fi
}

# Function to clean up temporary files and resources
cleanup() {
    print_message "info" "Cleaning up temporary files and resources..."

    # Remove any temporary files created during the script execution
    local temp_files=(
        "/tmp/route53-change-batch.json"
        "/tmp/cloudfront-distribution-config.json"
        "/tmp/certificate-validation-records.json"
    )

    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm "$file"
            print_message "info" "Removed temporary file: $file"
        fi
    done

    # Remove any temporary environment variables
    unset HOSTED_ZONE_ID
    unset DISTRIBUTION_ID
    unset CERT_ARN

    # Add any other cleanup tasks here
    # For example, you might want to remove any temporary IAM roles or policies created during deployment

    print_message "success" "Cleanup completed."
}

# Function to check and renew SSL certificate if necessary
check_and_renew_certificate() {
    if [ "$CERT_EXISTS" = true ]; then
        EXPIRY_DATE=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query 'Certificate.NotAfter' --output text --profile $AWS_CLI_PROFILE)
        DAYS_TO_EXPIRY=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))
        if [ $DAYS_TO_EXPIRY -lt 30 ]; then
            print_message "warning" "SSL certificate will expire in $DAYS_TO_EXPIRY days. Renewing..."
            # Add renewal logic here
        else
            print_message "info" "SSL certificate is valid for $DAYS_TO_EXPIRY more days."
        fi
    fi
}

# Function to check nameservers
check_nameservers() {
    if [ "$DNS_METHOD" = "manual" ]; then
        print_message "info" "Manual DNS configuration selected. Skipping nameserver check."
        return 0
    fi

    print_message "info" "Checking nameservers for $DOMAIN_NAME..."

    # Get the Hosted Zone ID for the domain
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN_NAME --query 'HostedZones[0].Id' --output text --profile $AWS_CLI_PROFILE)

    if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" = "None" ]; then
        print_message "error" "Could not find a Route 53 hosted zone for $DOMAIN_NAME"
        print_message "info" "Please create a hosted zone for your domain in Route 53 before proceeding."
        exit 1
    fi

    # Get Route 53 nameservers for the domain
    ROUTE53_NS=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --query "DelegationSet.NameServers" --output text --profile $AWS_CLI_PROFILE)

    if [ -z "$ROUTE53_NS" ]; then
        print_message "error" "Could not retrieve Route 53 nameservers. Please check your AWS configuration."
        exit 1
    fi

    # Get current nameservers for the domain
    CURRENT_NS=$(dig +short NS $DOMAIN_NAME | sort)

    if [ -z "$CURRENT_NS" ]; then
        print_message "error" "Could not retrieve current nameservers for $DOMAIN_NAME. Please check if the domain exists."
        exit 1
    fi

    # Compare nameservers
    if [ "$ROUTE53_NS" = "$CURRENT_NS" ]; then
        print_message "success" "Nameservers are correctly set to Route 53."
    else
        print_message "warning" "Nameservers are not correctly set to Route 53."
        print_message "info" "Current nameservers:"
        echo "$CURRENT_NS"
        print_message "info" "Expected Route 53 nameservers:"
        echo "$ROUTE53_NS"
        print_message "info" "Please update your domain's nameservers at your registrar to the Route 53 nameservers listed above."
        print_message "info" "After updating, it may take up to 48 hours for the changes to propagate."
        print_message "info" "Once propagated, run this script again to continue with the deployment."
        exit 1
    fi
}

# Function to get CloudFront domain
get_cloudfront_domain() {
    CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE)
    if [ -z "$CLOUDFRONT_DOMAIN" ]; then
        print_message "error" "Failed to retrieve CloudFront domain name."
        exit 1
    fi
}

# Main execution flow
set -e  # Exit immediately if a command exits with a non-zero status
trap 'rollback' ERR  # Call rollback function on any error

print_message "info" "Starting deployment process..."

# Check if AWS CLI is installed and configured correctly
if ! command -v aws &> /dev/null; then
    print_message "warning" "AWS CLI is not installed."
    read -p "Do you want to attempt to install AWS CLI? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_message "info" "Installing AWS CLI..."
        install_aws_cli &
        spinner $!
        if command -v aws &> /dev/null; then
            print_message "success" "AWS CLI installed successfully."
        else
            print_message "error" "AWS CLI installation failed. Please install it manually."
            exit 1
        fi
    else
        print_message "error" "Please install AWS CLI manually and run this script again."
        exit 1
    fi
fi

check_aws_cli_config

# Validate S3 bucket name
if ! validate_bucket_name "$S3_BUCKET"; then
    print_message "error" "Invalid S3 bucket name. Please correct it in the .env file."
    exit 1
fi

# Check existing resources
check_existing_resources

# Create and configure S3 bucket (if it doesn't exist)
if [ "$S3_EXISTS" = false ]; then
    print_message "info" "Creating and configuring S3 bucket..."
    create_and_configure_s3_bucket &
    spinner $!
    S3_BUCKET_CREATED=true
else
    print_message "info" "Using existing S3 bucket..."
    check_s3_permissions
fi

# Verify S3 bucket configuration
print_message "info" "Verifying S3 bucket configuration..."
if ! aws s3api get-bucket-website --bucket $S3_BUCKET --profile $AWS_CLI_PROFILE &>/dev/null; then
    print_message "error" "S3 bucket is not configured for static website hosting. Attempting to reconfigure..."
    create_and_configure_s3_bucket
fi

# Build the React app
build_react_app

# Check for valid certificate
if validate_ssl_certificate; then
    print_message "info" "Using existing valid SSL certificate: $CERTIFICATE_ARN"
else
    print_message "info" "No valid certificate found. Requesting a new one..."
    if request_and_validate_certificate; then
        CERTIFICATE_CREATED=true
        print_message "success" "New certificate created and validated successfully."
    else
        print_message "error" "Failed to create and validate a new certificate."
        exit 1
    fi
fi

# Create or get CloudFront distribution
if [ "$CF_EXISTS" = false ]; then
    print_message "info" "Setting up CloudFront distribution..."
    create_or_get_cloudfront_distribution
    CLOUDFRONT_DISTRIBUTION_CREATED=true
else
    print_message "info" "Using existing CloudFront distribution..."
    validate_cloudfront_distribution
fi

# Get CloudFront domain
get_cloudfront_domain

# Invalidate CloudFront cache
print_message "info" "Initiating CloudFront cache invalidation..."
INVALIDATION_ID=$(aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_DISTRIBUTION_ID --paths "/*" --query 'Invalidation.Id' --output text --profile $AWS_CLI_PROFILE)

if [ -n "$INVALIDATION_ID" ]; then
    print_message "success" "CloudFront invalidation initiated. ID: $INVALIDATION_ID"
    print_message "info" "The invalidation process has started but may take up to 15 minutes to complete."
    print_message "info" "Your updated content may be available sooner, but full propagation can take some time."
    print_message "info" "You can check the status of the invalidation in the AWS CloudFront console."
else
    print_message "warning" "Failed to initiate CloudFront invalidation. You may need to invalidate the cache manually."
fi

print_message "info" "Continuing with the deployment process..."

# Main execution flow for DNS updates
if [ "$DNS_METHOD" = "route53" ]; then
    create_or_get_hosted_zone_and_check_nameservers
    if ! check_dns_propagation; then
        read -p "Do you want to update DNS using Route 53? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_route53_dns
        else
            print_message "warning" "Skipping Route 53 DNS update."
        fi
    else
        print_message "info" "DNS is already correctly configured. No updates needed."
    fi
elif [ "$DNS_METHOD" = "manual" ]; then
    if ! check_dns_propagation; then
        print_message "info" "Manual DNS configuration required."
        provide_manual_dns_info
    else
        print_message "info" "DNS is already correctly configured. No manual updates needed."
    fi
else
    print_message "error" "Invalid DNS_METHOD in .env file. Please set it to either 'route53' or 'manual'."
    exit 1
fi

# Deployment summary
print_message "success" "Deployment process completed."
echo
print_message "info" "Deployment Summary:"
echo "  • S3 Bucket: $S3_BUCKET"
echo "  • CloudFront Distribution: $CLOUDFRONT_DISTRIBUTION_ID"
echo "  • Domain: $DOMAIN_NAME"
echo "  • SSL Certificate ARN: $CERTIFICATE_ARN"

if [ "$CF_EXISTS" = true ]; then
    echo
    print_message "success" "Your updated website should be accessible at https://$DOMAIN_NAME"
    echo "Note: It may take a few minutes for changes to propagate through CloudFront."
elif [ "$DNS_METHOD" = "manual" ]; then
    echo
    print_message "warning" "Next Steps:"
    echo "  1. Update your DNS records as instructed (if not already done)."
    echo "  2. Wait for DNS propagation (up to 48 hours)."
    echo "  3. Your website will be accessible at https://$DOMAIN_NAME"
else
    echo
    print_message "success" "Your website should be accessible at https://$DOMAIN_NAME"
    echo "Note: It may take a few minutes for changes to propagate."
fi

# Call the cleanup function
cleanup

# AWS configuration export
export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_PROFILE=$AWS_CLI_PROFILE