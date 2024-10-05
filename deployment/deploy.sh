#!/bin/bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
CONFIG_FILE="deployment/deploy-config.env"
if [ -f $CONFIG_FILE ]; then
    export $(grep -v '^#' $CONFIG_FILE | xargs)
else
    print_message "error" "Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Function to validate environment variables
validate_env_variables() {
    required_vars=("AWS_REGION" "S3_BUCKET" "AWS_CLI_PROFILE" "DOMAIN_NAME" "DNS_METHOD")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_message "error" "Required environment variable $var is not set."
            exit 1
        fi
    done
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
    if ! npm run build; then
        print_message "error" "React build failed. Check your application code."
        exit 1
    fi
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
    CERT_STATUS=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query "Certificate.Status" --output text --profile $AWS_CLI_PROFILE)
    if [ "$CERT_STATUS" != "ISSUED" ]; then
        print_message "error" "SSL certificate is not in ISSUED state. Current status: $CERT_STATUS"
        exit 1
    fi
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
    if ! dig +short $DOMAIN_NAME | grep -q $(aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE); then
        print_message "warning" "DNS changes may not have propagated yet. Your site might not be immediately accessible."
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
    sed -i.bak "s/CERTIFICATE_ARN=.*/CERTIFICATE_ARN=$CERT_ARN/" .env && rm .env.bak
    export CERTIFICATE_ARN=$CERT_ARN
}

# Function to create or get CloudFront distribution
create_or_get_cloudfront_distribution() {
    print_message "info" "Checking for existing CloudFront distribution..."
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0] == '${DOMAIN_NAME}'].Id" --output text --profile $AWS_CLI_PROFILE)
    
    if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
        print_message "info" "Creating new CloudFront distribution..."
        DISTRIBUTION_ID=$(aws cloudfront create-distribution \
            --origin-domain-name "${S3_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com" \
            --default-root-object "index.html" \
            --aliases "${DOMAIN_NAME}" "www.${DOMAIN_NAME}" \
            --default-cache-behavior '{"ViewerProtocolPolicy":"redirect-to-https","AllowedMethods":{"Quantity":2,"Items":["GET","HEAD"]},"MinTTL":0,"TargetOriginId":"S3-Website","ForwardedValues":{"QueryString":false,"Cookies":{"Forward":"none"}},"TrustedSigners":{"Enabled":false,"Quantity":0},"SmoothStreaming":false,"Compress":true}' \
            --enabled \
            --comment "Distribution for ${DOMAIN_NAME}" \
            --viewer-certificate "{\"ACMCertificateArn\":\"${CERTIFICATE_ARN}\",\"SSLSupportMethod\":\"sni-only\",\"MinimumProtocolVersion\":\"TLSv1.2_2021\"}" \
            --query "Distribution.Id" \
            --output text \
            --profile $AWS_CLI_PROFILE)
        print_message "success" "New CloudFront distribution created with ID: $DISTRIBUTION_ID"
    else
        print_message "info" "Existing CloudFront distribution found with ID: $DISTRIBUTION_ID"
        # Update the existing distribution with the new certificate
        aws cloudfront update-distribution --id $DISTRIBUTION_ID \
            --viewer-certificate "{\"ACMCertificateArn\":\"${CERTIFICATE_ARN}\",\"SSLSupportMethod\":\"sni-only\",\"MinimumProtocolVersion\":\"TLSv1.2_2021\"}" \
            --profile $AWS_CLI_PROFILE
        print_message "success" "Updated CloudFront distribution with new certificate."
    fi
    
    # Update .env file with the distribution ID
    sed -i.bak "s/CLOUDFRONT_DISTRIBUTION_ID=.*/CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID/" .env && rm .env.bak
    export CLOUDFRONT_DISTRIBUTION_ID=$DISTRIBUTION_ID
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
    
    # Get certificate validation records
    CERT_VALIDATION_RECORDS=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query "Certificate.DomainValidationOptions[].ResourceRecord" --output json --profile $AWS_CLI_PROFILE)
    
    print_message "info" "To point your domain to this website and validate your SSL certificate, create the following DNS records at your DNS provider:"
    echo
    echo "1. For the root domain (${DOMAIN_NAME}):"
    echo "   Type: A"
    echo "   Name: @"
    echo "   Value: Set up an ALIAS record pointing to ${CF_DOMAIN}"
    echo
    echo "2. For the www subdomain (www.${DOMAIN_NAME}):"
    echo "   Type: CNAME"
    echo "   Name: www"
    echo "   Value: ${CF_DOMAIN}"
    echo
    echo "3. For SSL certificate validation:"
    echo "$CERT_VALIDATION_RECORDS" | jq -r '.[] | "   Type: \(.Type)\n   Name: \(.Name)\n   Value: \(.Value)\n"'
    echo
    echo "Note: The exact steps to create these records may vary depending on your DNS provider."
    echo "Some providers may not support ALIAS records for the root domain. In that case, you may need to use CNAME flattening or ANAME records if available."
    echo
    echo "After updating your DNS records:"
    echo "1. The CloudFront records (steps 1 and 2) will allow your domain to point to your website."
    echo "2. The certificate validation record(s) (step 3) will allow AWS to validate your SSL certificate."
    echo
    echo "It may take up to 48 hours for DNS changes to propagate fully, although they often take effect much sooner."
    echo "Certificate validation may take several minutes to a few hours after the DNS records are updated."
}

# Function to create S3 bucket and configure it for static website hosting
create_and_configure_s3_bucket() {
    print_message "info" "Checking if S3 bucket exists..."
    if aws s3 ls "s3://$S3_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        print_message "info" "S3 bucket does not exist. Creating bucket $S3_BUCKET..."
        if ! OUTPUT=$(aws s3 mb s3://$S3_BUCKET 2>&1); then
            print_message "error" "Failed to create S3 bucket: $OUTPUT"
            exit 1
        fi
        
        print_message "success" "S3 bucket created successfully."
    else
        print_message "info" "S3 bucket already exists."
    fi

    print_message "info" "Configuring bucket for static website hosting..."
    aws s3 website s3://$S3_BUCKET --index-document index.html --error-document index.html --profile $AWS_CLI_PROFILE

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
    
    echo "$BUCKET_POLICY" | aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file:///dev/stdin --profile $AWS_CLI_PROFILE

    if [ $? -eq 0 ]; then
        print_message "success" "S3 bucket configured successfully for static website hosting."
    else
        print_message "error" "Failed to configure S3 bucket for static website hosting. Exiting."
        exit 1
    fi
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
    
    # Check SSL certificate
    CERT_ARN=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE)
    if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" = "None" ]; then
        CERT_EXISTS=false
    else
        CERT_EXISTS=true
        print_message "info" "SSL certificate already exists: $CERT_ARN"
    fi
}

# Rollback function
rollback() {
    print_message "warning" "Deployment failed. Rolling back changes..."
    # Add rollback logic here (e.g., reverting S3 bucket to previous state)
}

# Main execution flow
set -e  # Exit immediately if a command exits with a non-zero status
trap 'rollback' ERR  # Call rollback function on any error

print_message "info" "Starting deployment process..."

# Validate environment variables
validate_env_variables

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
else
    print_message "info" "Using existing S3 bucket..."
    check_s3_permissions
fi

# Build the React app
print_message "info" "Building the React app..."
build_react_app &
spinner $!

# Sync build folder with S3 bucket
print_message "info" "Uploading to S3 bucket..."
aws s3 sync build/ s3://$S3_BUCKET --delete --profile $AWS_CLI_PROFILE &
spinner $!

# Create or get CloudFront distribution
if [ "$CF_EXISTS" = false ]; then
    print_message "info" "Setting up CloudFront distribution..."
    create_or_get_cloudfront_distribution &
    spinner $!
else
    print_message "info" "Using existing CloudFront distribution..."
    validate_cloudfront_distribution
fi

# Validate SSL certificate
validate_ssl_certificate

# Invalidate CloudFront cache
print_message "info" "Invalidating CloudFront cache..."
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_DISTRIBUTION_ID --paths "/*" --profile $AWS_CLI_PROFILE &
spinner $!

# Handle DNS updates
if [ "$DNS_METHOD" = "route53" ]; then
    if [ "$CF_EXISTS" = false ]; then
        print_message "info" "Configuring Route 53..."
        create_or_get_hosted_zone_and_check_nameservers &
        spinner $!
        check_route53_hosted_zone
        read -p "Do you want to update DNS using Route 53? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_route53_dns &
            spinner $!
            check_dns_propagation
        else
            print_message "warning" "Skipping Route 53 DNS update."
        fi
    else
        print_message "info" "DNS already configured. Skipping Route 53 update."
    fi
elif [ "$DNS_METHOD" = "manual" ]; then
    if [ "$CF_EXISTS" = false ]; then
        print_message "info" "Manual DNS configuration required."
        provide_manual_dns_info
        print_message "warning" "Please update your DNS records as instructed above."
    else
        print_message "info" "DNS already configured. No manual updates needed."
    fi
else
    print_message "error" "Invalid DNS_METHOD in .env file. Please set it to either 'route53' or 'manual'."
    exit 1
fi

# Deployment summary
print_message "success" "Deployment process completed."
echo -e "\n${BLUE}Deployment Summary:${NC}"
echo -e "  • S3 Bucket: ${GREEN}$S3_BUCKET${NC}"
echo -e "  • CloudFront Distribution: ${GREEN}$CLOUDFRONT_DISTRIBUTION_ID${NC}"
echo -e "  • Domain: ${GREEN}$DOMAIN_NAME${NC}"
echo -e "  • SSL Certificate ARN: ${GREEN}$CERTIFICATE_ARN${NC}"

if [ "$CF_EXISTS" = true ]; then
    echo -e "\n${GREEN}Your updated website should be accessible at https://$DOMAIN_NAME${NC}"
    echo "Note: It may take a few minutes for changes to propagate through CloudFront."
elif [ "$DNS_METHOD" = "manual" ]; then
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "  1. Update your DNS records as instructed (if not already done)."
    echo "  2. Wait for DNS propagation (up to 48 hours)."
    echo "  3. Your website will be accessible at https://$DOMAIN_NAME"
else
    echo -e "\n${GREEN}Your website should be accessible at https://$DOMAIN_NAME${NC}"
    echo "Note: It may take a few minutes for changes to propagate."
fi

export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_PROFILE=$AWS_CLI_PROFILE

LOG_FILE="deployment/deploy.log"
exec > >(tee -i $LOG_FILE)
exec 2>&1