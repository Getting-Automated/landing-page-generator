# Set error action preference to stop on errors
$ErrorActionPreference = 'Stop'

# Start logging
$LogFile = "deploy.log"
Start-Transcript -Path $LogFile -Append

# Color definitions
$Colors = @{
    'Red'    = 'Red'
    'Green'  = 'Green'
    'Yellow' = 'Yellow'
    'Blue'   = 'Blue'
    'NC'     = 'White'  # No Color
}

# Error flags
$S3_BUCKET_CREATED = $false
$CLOUDFRONT_DISTRIBUTION_CREATED = $false
$CERTIFICATE_CREATED = $false
$ROUTE53_RECORDS_CREATED = $false

# Function to print formatted messages
function Write-Message {
    param(
        [string]$Type,
        [string]$Message
    )

    switch ($Type) {
        "info" {
            Write-Host "ℹ️ INFO: $Message" -ForegroundColor $Colors['Blue']
        }
        "success" {
            Write-Host "✅ SUCCESS: $Message" -ForegroundColor $Colors['Green']
        }
        "warning" {
            Write-Host "⚠️ WARNING: $Message" -ForegroundColor $Colors['Yellow']
        }
        "error" {
            Write-Host "❌ ERROR: $Message" -ForegroundColor $Colors['Red']
        }
    }
}

# Rollback function
function Rollback {
    Write-Message "warning" "Deployment failed. Rolling back changes..."

    # Rollback S3 bucket
    if ($S3_BUCKET_CREATED -and $S3_BUCKET) {
        Write-Message "info" "Deleting newly created S3 bucket: $S3_BUCKET"
        aws s3 rb "s3://$S3_BUCKET" --force --profile $AWS_CLI_PROFILE
    }

    # Rollback CloudFront distribution
    if ($CLOUDFRONT_DISTRIBUTION_CREATED -and $CLOUDFRONT_DISTRIBUTION_ID) {
        Write-Message "info" "Deleting newly created CloudFront distribution: $CLOUDFRONT_DISTRIBUTION_ID"
        $ETag = aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query 'ETag' --output text --profile $AWS_CLI_PROFILE
        aws cloudfront delete-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --if-match $ETag --profile $AWS_CLI_PROFILE
    }

    # Rollback SSL certificate
    if ($CERTIFICATE_CREATED -and $CERTIFICATE_ARN) {
        Write-Message "info" "Deleting newly created SSL certificate: $CERTIFICATE_ARN"
        aws acm delete-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --profile $AWS_CLI_PROFILE
    }

    # Rollback Route 53 records
    if ($ROUTE53_RECORDS_CREATED -and $HOSTED_ZONE_ID) {
        Write-Message "info" "Deleting newly created Route 53 records"
        # Implement the logic to delete specific records here
        # Note: You need to keep track of the changes made to Route 53 to roll them back
    }

    Write-Message "info" "Rollback completed."
}

# Trap for unhandled exceptions
$global:ErrorActionPreference = 'Stop'
$Error.Clear()
# Remove or comment out this line
# Register-EngineEvent PowerShell.Exiting -Action { Rollback }

# Function to load configuration
function Load-Configuration {
    $ConfigFile = Join-Path $PSScriptRoot "deploy-config.env"
    Write-Message "info" "Attempting to load configuration from: $ConfigFile"
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | ForEach-Object {
            if ($_ -notmatch '^\s*#' -and $_ -match '^\s*(\S+?)\s*=\s*(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim('"').Trim()
                Set-Variable -Name $key -Value $value -Scope Script
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
                Write-Host "Set $key to '$value'"
            }
        }
    } else {
        Write-Message "error" "Configuration file not found at: $ConfigFile"
        exit 1
    }
}

# Validate environment variables and set S3_BUCKET
function Validate-EnvVariables {
    $required_vars = @("AWS_REGION", "AWS_CLI_PROFILE", "DOMAIN_NAME", "DNS_METHOD")
    foreach ($var in $required_vars) {
        $value = Get-Variable -Name $var -ValueOnly -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($value)) {
            Write-Message "error" "Required environment variable $var is not set or is empty."
            Write-Host "Current value of $var`: '$value'"
            exit 1
        }
    }
    # Set S3_BUCKET to DOMAIN_NAME
    $S3_BUCKET = $DOMAIN_NAME
    Set-Variable -Name "S3_BUCKET" -Value $S3_BUCKET -Scope Script
    [Environment]::SetEnvironmentVariable("S3_BUCKET", $S3_BUCKET, "Process")
    Write-Host "Set S3_BUCKET to '$S3_BUCKET'"
}

# Function to validate AWS configuration
function Validate-AwsConfig {
    Write-Message "info" "Validating AWS configuration..."

    # Validate AWS region
    $regions = aws ec2 describe-regions --region $AWS_REGION --query "Regions[?RegionName=='$AWS_REGION'].RegionName" --output text --profile $AWS_CLI_PROFILE 2>$null
    if ($regions -eq "") {
        Write-Message "error" "Invalid AWS region: $AWS_REGION"
        exit 1
    }

    # Validate AWS CLI profile
    try {
        aws sts get-caller-identity --profile $AWS_CLI_PROFILE >$null
    } catch {
        Write-Message "error" "Invalid or unconfigured AWS CLI profile: $AWS_CLI_PROFILE"
        exit 1
    }

    Write-Message "success" "AWS configuration is valid."
}

# Function to check AWS CLI configuration
function Check-AwsCliConfig {
    try {
        aws sts get-caller-identity --profile $AWS_CLI_PROFILE >$null
    } catch {
        Write-Message "error" "AWS CLI is not configured correctly or the profile '$AWS_CLI_PROFILE' doesn't exist."
        exit 1
    }
}

# Function to validate S3 bucket name
function Validate-BucketName {
    param(
        [string]$BucketName
    )

    Write-Host "Validating bucket name: '$BucketName'"

    # Check if bucket name is empty
    if ([string]::IsNullOrEmpty($BucketName)) {
        Write-Message "error" "S3 bucket name is empty."
        return $false
    }

    # Check length (3-63 characters)
    if ($BucketName.Length -lt 3 -or $BucketName.Length -gt 63) {
        Write-Message "error" "S3 bucket name must be between 3 and 63 characters long."
        return $false
    }

    # Check if it's a valid domain name format
    if ($BucketName -notmatch '^[a-z0-9][a-z0-9.-]*[a-z0-9]$') {
        Write-Message "error" "S3 bucket name must be in valid domain name format."
        Write-Message "info" "It should contain only lowercase letters, numbers, hyphens, and periods."
        Write-Message "info" "It must start and end with a letter or number."
        return $false
    }

    # Check for consecutive periods
    if ($BucketName -match '\.\.') {
        Write-Message "error" "S3 bucket name cannot contain consecutive periods."
        return $false
    }

    # Check if it's not an IP address
    if ($BucketName -match '^[0-9]{1,3}(\.[0-9]{1,3}){3}$') {
        Write-Message "error" "S3 bucket name cannot be formatted as an IP address."
        return $false
    }

    return $true
}

# Function to install AWS CLI
function Install-AwsCli {
    if ($IsLinux) {
        Write-Message "info" "Attempting to install AWS CLI on Linux..."
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -OutFile "awscliv2.zip"
        Expand-Archive -Path "awscliv2.zip" -DestinationPath "."
        sudo ./aws/install
        Remove-Item -Recurse -Force "aws", "awscliv2.zip"
    } elseif ($IsMacOS) {
        Write-Message "info" "Attempting to install AWS CLI on macOS..."
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.pkg" -OutFile "AWSCLIV2.pkg"
        sudo installer -pkg "AWSCLIV2.pkg" -target /
        Remove-Item "AWSCLIV2.pkg"
    } else {
        Write-Message "error" "Unsupported operating system for automatic AWS CLI installation."
        exit 1
    }
}

# Function to check S3 permissions
function Check-S3Permissions {
    try {
        aws s3 ls "s3://$S3_BUCKET" --profile $AWS_CLI_PROFILE >$null
    } catch {
        Write-Message "error" "Unable to access S3 bucket. Check your permissions."
        exit 1
    }
}

# Function to build React app
function Build-ReactApp {
    # Store the current directory
    $ScriptDir = Get-Location

    # Navigate to the parent directory where the React app is located
    Set-Location ".."

    # Build the React app
    Write-Message "info" "Building the React app..."
    if (npm run build) {
        Write-Message "success" "React app built successfully."
    } else {
        Write-Message "error" "Failed to build React app. Check your application code and build configuration."
        Set-Location $ScriptDir  # Return to the original directory
        exit 1
    }

    # Check if build directory exists
    if (-not (Test-Path "build")) {
        Write-Message "error" "Build directory 'build/' does not exist. The build process may have failed."
        Set-Location $ScriptDir  # Return to the original directory
        exit 1
    }

    # Sync build folder with S3 bucket
    Write-Message "info" "Uploading to S3 bucket..."
    if (aws s3 sync "build/" "s3://$S3_BUCKET" --delete --profile $AWS_CLI_PROFILE) {
        Write-Message "success" "Successfully uploaded build to S3 bucket."
    } else {
        Write-Message "error" "Failed to upload build to S3 bucket. Check your AWS permissions and S3 bucket configuration."
        Set-Location $ScriptDir  # Return to the original directory
        exit 1
    }

    # Return to the original directory
    Set-Location $ScriptDir
}

# Function to validate CloudFront distribution
function Validate-CloudFrontDistribution {
    try {
        aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --profile $AWS_CLI_PROFILE >$null
    } catch {
        Write-Message "error" "Unable to access CloudFront distribution. Check your permissions and distribution ID."
        exit 1
    }
}

# Function to validate SSL certificate
function Validate-SslCertificate {
    Write-Message "info" "Validating existing SSL certificate..."

    # Get the domains the certificate is valid for
    $CertDetails = aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query 'Certificate.{Domains:DomainValidationOptions[].DomainName,Status:Status}' --output json --profile $AWS_CLI_PROFILE | ConvertFrom-Json

    Write-Message "info" "Certificate ARN: $CERTIFICATE_ARN"
    Write-Message "info" "Certificate is valid for: $($CertDetails.Domains -join ', ')"
    Write-Message "info" "Intended domain: $DOMAIN_NAME"
    Write-Message "info" "Certificate status: $($CertDetails.Status)"

    # Check if the intended domain is in the list of valid domains
    $domainValid = $CertDetails.Domains -contains $DOMAIN_NAME -or $CertDetails.Domains -contains "www.$DOMAIN_NAME"
    
    if (-not $domainValid) {
        Write-Message "error" "The existing certificate (ARN: $CERTIFICATE_ARN) does not support the domain $DOMAIN_NAME or www.$DOMAIN_NAME"
        Write-Message "info" "Certificate is valid for: $($CertDetails.Domains -join ', ')"
        Write-Message "warning" "A new certificate needs to be requested for $DOMAIN_NAME"
        Write-Message "info" "Please remove the existing certificate ARN from your configuration and run the script again to request a new certificate."
        return $false
    }

    # Check certificate status
    if ($CertDetails.Status -ne "ISSUED") {
        Write-Message "error" "Certificate is not in ISSUED state. Current status: $($CertDetails.Status)"
        Write-Message "info" "Here are the steps to resolve this issue:"

        # Get the CNAME records for validation
        $CnameRecords = aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query 'Certificate.DomainValidationOptions[].ResourceRecord' --output json --profile $AWS_CLI_PROFILE | ConvertFrom-Json

        if ($DNS_METHOD -eq "route53") {
            Write-Message "info" "1. Ensure your domain's nameservers are correctly set to Route 53:"
            Write-Message "info" "   - Go to your domain registrar's website"
            Write-Message "info" "   - Update the nameservers to the Route 53 nameservers"
            Write-Message "info" "   - Wait for the nameserver changes to propagate (up to 48 hours)"
            Write-Message "info" "2. Once nameservers are updated, go to the AWS Certificate Manager (ACM) console: https://console.aws.amazon.com/acm/"
            Write-Message "info" "3. Find the certificate for $DOMAIN_NAME"
            Write-Message "info" "4. Check the 'Status' and 'Domain' columns for more information"
            Write-Message "info" "If the status is 'Pending validation':"
            Write-Message "info" "  a. Click on the certificate to view details"
            Write-Message "info" "  b. In the 'Domains' section, look for the CNAME records you need to add"
            Write-Message "info" "  c. These CNAME records should be automatically added to Route 53"
            Write-Message "info" "  d. If not, you can create the record sets manually in Route 53"
        } else {
            Write-Message "info" "For manual DNS configuration, please add the following CNAME records to your DNS provider:"
            foreach ($record in $CnameRecords) {
                Write-Host "   Name: $($record.Name)"
                Write-Host "   Value: $($record.Value)"
                Write-Host ""
            }
            Write-Message "info" "Steps to add these records:"
            Write-Message "info" "1. Log in to your DNS provider's management console"
            Write-Message "info" "2. Navigate to the DNS management section for $DOMAIN_NAME"
            Write-Message "info" "3. Add each CNAME record listed above"
            Write-Message "info" "4. Save your changes"
        }

        Write-Message "info" "5. Wait for the DNS changes to propagate (this can take up to 48 hours)"
        Write-Message "info" "6. Once the certificate status changes to 'Issued', run this script again"

        Write-Message "info" "If you continue to have issues or the status is different:"
        Write-Message "info" "  - Check the AWS ACM troubleshooting guide: https://docs.aws.amazon.com/acm/latest/userguide/troubleshooting.html"
        Write-Message "info" "  - Verify that you have the necessary permissions to validate the certificate"

        return $false
    }

    Write-Message "success" "SSL certificate is valid for $DOMAIN_NAME and is in ISSUED state."
    return $true
}

# Function to check Route 53 hosted zone
function Check-Route53HostedZone {
    try {
        aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --profile $AWS_CLI_PROFILE >$null
    } catch {
        Write-Message "error" "Unable to access Route 53 hosted zone. Check your permissions and hosted zone ID."
        exit 1
    }
}

# Function to check DNS propagation
function Check-DnsPropagation {
    Write-Message "info" "Checking DNS propagation for $DOMAIN_NAME..."

    $CF_DOMAIN = aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE

    $DNSResult = Resolve-DnsName -Name $DOMAIN_NAME -Type A -ErrorAction SilentlyContinue
    if ($DNSResult) {
        $IPAddresses = $DNSResult.IPAddress
        Write-Message "info" "DNS is resolving to: $($IPAddresses -join ', ')"
    } else {
        Write-Message "warning" "DNS changes may not have propagated yet. Your site might not be immediately accessible."
    }
}

# Function to request and validate certificate
function Request-AndValidateCertificate {
    Write-Message "info" "Requesting new SSL certificate..."
    $CertArn = aws acm request-certificate --domain-name "$DOMAIN_NAME" --validation-method DNS --subject-alternative-names "www.$DOMAIN_NAME" --region us-east-1 --query "CertificateArn" --output text --profile $AWS_CLI_PROFILE

    if ([string]::IsNullOrEmpty($CertArn)) {
        Write-Message "error" "Failed to request new certificate."
        exit 1
    }

    Write-Message "success" "Certificate requested. ARN: $CertArn"
    $CERTIFICATE_ARN = $CertArn
    Set-Variable -Name "CERTIFICATE_ARN" -Value $CERTIFICATE_ARN -Scope Script
    [Environment]::SetEnvironmentVariable("CERTIFICATE_ARN", $CERTIFICATE_ARN, "Process")

    # Update .env file with the new certificate ARN
    $ConfigFile = Join-Path $PSScriptRoot "deploy-config.env"
    if (Test-Path $ConfigFile) {
        $ConfigContent = Get-Content $ConfigFile
        $UpdatedContent = $ConfigContent -replace "CERTIFICATE_ARN=.*", "CERTIFICATE_ARN=$CertArn"
        $UpdatedContent | Set-Content $ConfigFile
        Write-Message "info" "Updated configuration file with new certificate ARN."
    } else {
        Write-Message "warning" "Could not update configuration file. Please manually set CERTIFICATE_ARN=$CertArn in your deploy-config.env file."
    }

    # Get the CNAME records for validation
    $DnsValidationRecords = aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query 'Certificate.DomainValidationOptions[].ResourceRecord' --output json --profile $AWS_CLI_PROFILE | ConvertFrom-Json

    if ($DNS_METHOD -eq "route53") {
        Write-Message "info" "Creating DNS validation records in Route 53..."
        
        # Create the validation records in Route 53
        foreach ($record in $DnsValidationRecords) {
            $Name = $record.Name
            $Value = $record.Value

            $ChangeBatch = @{
                "Changes" = @(
                    @{
                        "Action" = "UPSERT"
                        "ResourceRecordSet" = @{
                            "Name" = $Name
                            "Type" = "CNAME"
                            "TTL"  = 300
                            "ResourceRecords" = @(
                                @{
                                    "Value" = $Value
                                }
                            )
                        }
                    }
                )
            }

            $ChangeBatchJson = $ChangeBatch | ConvertTo-Json -Depth 10

            aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch $ChangeBatchJson --profile $AWS_CLI_PROFILE
        }

        Write-Message "success" "DNS validation records created in Route 53."
        Write-Message "info" "Waiting for certificate validation. This may take up to 30 minutes..."
        
        # Wait for certificate validation
        aws acm wait certificate-validated --certificate-arn $CertArn --region us-east-1 --profile $AWS_CLI_PROFILE
        
        $CertStatus = aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query 'Certificate.Status' --output text --profile $AWS_CLI_PROFILE
        
        if ($CertStatus -eq "ISSUED") {
            Write-Message "success" "Certificate validated and issued successfully."
        } else {
            Write-Message "error" "Certificate validation failed. Status: $CertStatus"
            exit 1
        }
        $script:deploymentComplete = $true
        $script:deploymentPaused = $false
        return "complete"
    } else {
        Write-Message "info" "For manual DNS configuration, please add the following CNAME records to your DNS provider:"
        foreach ($record in $DnsValidationRecords) {
            Write-Host "   Name: $($record.Name)"
            Write-Host "   Value: $($record.Value)"
            Write-Host ""
        }
        Write-Message "info" "After adding these records, the certificate will be validated automatically."
        Write-Message "info" "This process may take up to 30 minutes. Please run this script again after DNS propagation to complete the deployment."
        $script:deploymentComplete = $false
        $script:deploymentPaused = $true
        return "paused"
    }
}

# Function to create or get CloudFront distribution
function Create-OrGetCloudFrontDistribution {
    Write-Message "info" "Checking for existing CloudFront distribution..."
    $ExistingDist = aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[?contains(@, '$DOMAIN_NAME')]].Id" --output text --profile $AWS_CLI_PROFILE

    if ([string]::IsNullOrEmpty($ExistingDist)) {
        Write-Message "info" "Creating new CloudFront distribution..."

        # Get the certificate ARN
        $CertArn = aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE

        if ([string]::IsNullOrEmpty($CertArn)) {
            Write-Message "error" "No certificate found for $DOMAIN_NAME. Please ensure the certificate exists in ACM."
            exit 1
        }

        # Create the CloudFront distribution configuration
        $DistributionConfig = @{
            "CallerReference" = "$(Get-Date -UFormat %s)"
            "Aliases" = @{
                "Quantity" = 2
                "Items"    = @("$DOMAIN_NAME", "www.$DOMAIN_NAME")
            }
            "DefaultRootObject" = "index.html"
            "Origins" = @{
                "Quantity" = 1
                "Items"    = @(
                    @{
                        "Id"               = "S3-Website"
                        "DomainName"       = "$S3_BUCKET.s3-website-$AWS_REGION.amazonaws.com"
                        "CustomOriginConfig" = @{
                            "HTTPPort"             = 80
                            "HTTPSPort"            = 443
                            "OriginProtocolPolicy" = "http-only"
                        }
                    }
                )
            }
            "DefaultCacheBehavior" = @{
                "TargetOriginId"       = "S3-Website"
                "ViewerProtocolPolicy" = "redirect-to-https"
                "AllowedMethods" = @{
                    "Quantity" = 2
                    "Items"    = @("GET", "HEAD")
                    "CachedMethods" = @{
                        "Quantity" = 2
                        "Items"    = @("GET", "HEAD")
                    }
                }
                "ForwardedValues" = @{
                    "QueryString" = $false
                    "Cookies"     = @{
                        "Forward" = "none"
                    }
                }
                "MinTTL"    = 0
                "DefaultTTL" = 300
                "MaxTTL"    = 1200
                "Compress"  = $true
            }
            "Comment"           = "Distribution for $DOMAIN_NAME"
            "Enabled"           = $true
            "ViewerCertificate" = @{
                "ACMCertificateArn"      = "$CertArn"
                "SSLSupportMethod"       = "sni-only"
                "MinimumProtocolVersion" = "TLSv1.2_2021"
            }
        }

        $DistributionConfigJson = @{
            "DistributionConfig" = $DistributionConfig
        } | ConvertTo-Json -Depth 10

        # Create the CloudFront distribution
        $Response = aws cloudfront create-distribution --distribution-config $DistributionConfigJson --profile $AWS_CLI_PROFILE
        $CLOUDFRONT_DISTRIBUTION_ID = $Response | ConvertFrom-Json | Select-Object -ExpandProperty Distribution | Select-Object -ExpandProperty Id

        if ([string]::IsNullOrEmpty($CLOUDFRONT_DISTRIBUTION_ID)) {
            Write-Message "error" "Failed to create CloudFront distribution."
            exit 1
        }

        Write-Message "success" "CloudFront distribution created. ID: $CLOUDFRONT_DISTRIBUTION_ID"
        $CLOUDFRONT_DISTRIBUTION_CREATED = $true
    } else {
        $CLOUDFRONT_DISTRIBUTION_ID = $ExistingDist
        Write-Message "info" "Using existing CloudFront distribution. ID: $CLOUDFRONT_DISTRIBUTION_ID"
    }

    # Update .env file with the CloudFront distribution ID
    (Get-Content $ConfigFile) -replace "CLOUDFRONT_DISTRIBUTION_ID=.*", "CLOUDFRONT_DISTRIBUTION_ID=$CLOUDFRONT_DISTRIBUTION_ID" | Set-Content $ConfigFile
    Set-Variable -Name "CLOUDFRONT_DISTRIBUTION_ID" -Value $CLOUDFRONT_DISTRIBUTION_ID
}

# Function to create or get Route 53 hosted zone and check nameservers
function Create-OrGetHostedZoneAndCheckNameservers {
    Write-Message "info" "Checking for existing Route 53 hosted zone..."
    $HostedZoneId = aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --query "HostedZones[0].Id" --output text --profile $AWS_CLI_PROFILE

    if ([string]::IsNullOrEmpty($HostedZoneId) -or $HostedZoneId -eq "None") {
        Write-Message "info" "Creating new Route 53 hosted zone for $DOMAIN_NAME..."
        $HostedZoneId = aws route53 create-hosted-zone --name "$DOMAIN_NAME" --caller-reference "$(Get-Date -UFormat %s)" --query "HostedZone.Id" --output text --profile $AWS_CLI_PROFILE
        Write-Message "success" "New hosted zone created with ID: $HostedZoneId"
    } else {
        Write-Message "info" "Existing hosted zone found with ID: $HostedZoneId"
    }

    # Get Route 53 nameservers
    $R53Nameservers = aws route53 get-hosted-zone --id "$HostedZoneId" --query "DelegationSet.NameServers" --output text --profile $AWS_CLI_PROFILE

    # Get current nameservers from the domain registrar
    try {
        $CurrentNameservers = (Resolve-DnsName -Name $DOMAIN_NAME -Type NS).NameHost
    } catch {
        Write-Message "warning" "Could not retrieve current nameservers for $DOMAIN_NAME."
        $CurrentNameservers = @()
    }

    # Compare nameservers
    if ($R53Nameservers -eq $CurrentNameservers) {
        Write-Message "success" "Nameservers are correctly set to Route 53."
    } else {
        Write-Message "warning" "Nameservers are not correctly set to Route 53."
        Write-Message "warning" "Please update your domain's nameservers at your registrar to the following:"
        $R53Nameservers | ForEach-Object { Write-Host $_ }
        Write-Message "warning" "Current nameservers are:"
        $CurrentNameservers | ForEach-Object { Write-Host $_ }
        Write-Message "warning" "DNS updates will not take effect until nameservers are updated."
    }

    $HOSTED_ZONE_ID = $HostedZoneId
    Set-Variable -Name "HOSTED_ZONE_ID" -Value $HOSTED_ZONE_ID
}

# Function to update DNS using Route 53
function Update-Route53Dns {
    Write-Message "info" "Updating DNS records using Route 53..."

    # Get the CloudFront domain name
    $CF_DOMAIN = aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE

    if ([string]::IsNullOrEmpty($CF_DOMAIN)) {
        Write-Message "error" "Could not retrieve CloudFront domain name."
        return $false
    }

    # Create the Route 53 change batch
    $ChangeBatch = @{
        "Changes" = @(
            @{
                "Action" = "UPSERT"
                "ResourceRecordSet" = @{
                    "Name" = "$DOMAIN_NAME"
                    "Type" = "A"
                    "AliasTarget" = @{
                        "HostedZoneId"         = "Z2FDTNDATAQYW2"  # CloudFront Hosted Zone ID
                        "DNSName"              = $CF_DOMAIN
                        "EvaluateTargetHealth" = $false
                    }
                }
            },
            @{
                "Action" = "UPSERT"
                "ResourceRecordSet" = @{
                    "Name" = "www.$DOMAIN_NAME"
                    "Type" = "CNAME"
                    "TTL"  = 300
                    "ResourceRecords" = @(
                        @{
                            "Value" = $CF_DOMAIN
                        }
                    )
                }
            }
        )
    }

    $ChangeBatchJson = $ChangeBatch | ConvertTo-Json -Depth 10

    # Update the Route 53 record
    try {
        aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch $ChangeBatchJson --profile $AWS_CLI_PROFILE
        Write-Message "success" "DNS updated successfully. It may take some time for changes to propagate."
        $ROUTE53_RECORDS_CREATED = $true
    } catch {
        Write-Message "error" "Error updating DNS. Please check your AWS credentials and Route 53 configuration."
        exit 1
    }
}

# Function to provide manual DNS update information
function Provide-ManualDnsInfo {
    Write-Message "info" "Retrieving CloudFront and Certificate information..."

    # Get the CloudFront domain name
    $CF_DOMAIN = aws cloudfront get-distribution --id $CLOUDFRONT_DISTRIBUTION_ID --query "Distribution.DomainName" --output text --profile $AWS_CLI_PROFILE

    if ([string]::IsNullOrEmpty($CF_DOMAIN)) {
        Write-Message "error" "Could not retrieve CloudFront domain name."
        return $false
    }

    # Get certificate validation records
    $CertValidationRecords = aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1 --query "Certificate.DomainValidationOptions[].ResourceRecord" --output json --profile $AWS_CLI_PROFILE | ConvertFrom-Json

    Write-Message "info" "To point your domain to this website and validate your SSL certificate, create the following DNS records at your DNS provider:"
    Write-Host ""
    Write-Host "1. For the root domain ($DOMAIN_NAME):"
    Write-Host "   Option A (if your DNS provider supports ALIAS records for A records):"
    Write-Host "     Type: A"
    Write-Host "     Name: @"
    Write-Host "     Value: Set up an ALIAS record pointing to $CF_DOMAIN"
    Write-Host ""
    Write-Host "   Option B (if your DNS provider doesn't support ALIAS for A records):"
    Write-Host "     Type: CNAME"
    Write-Host "     Name: www"
    Write-Host "     Value: $CF_DOMAIN"
    Write-Host "     Then, set up a URL redirect from the root domain to www.$DOMAIN_NAME"
    Write-Host ""
    Write-Host "2. For the www subdomain (www.$DOMAIN_NAME):"
    Write-Host "   Type: CNAME"
    Write-Host "   Name: www"
    Write-Host "   Value: $CF_DOMAIN"
    Write-Host ""
    Write-Host "3. For SSL certificate validation:"
    foreach ($record in $CertValidationRecords) {
        Write-Host "   Type: $($record.Type)"
        Write-Host "   Name: $($record.Name)"
        Write-Host "   Value: $($record.Value)"
        Write-Host ""
    }
    Write-Message "warning" "Please update your DNS records as instructed above."
    Write-Message "info" "After updating, it may take up to 48 hours for DNS changes to propagate fully."
    Write-Message "info" "Certificate validation may take several minutes to a few hours after the DNS records are updated."
    Write-Message "info" "Once the changes have propagated, run this script again to complete the deployment."
}

# Function to create S3 bucket and configure it for static website hosting
function Create-AndConfigureS3Bucket {
    Write-Message "info" "Checking if S3 bucket exists..."
    try {
        aws s3 ls "s3://$S3_BUCKET" --profile $AWS_CLI_PROFILE >$null
        Write-Message "info" "S3 bucket already exists."
    } catch {
        Write-Message "info" "S3 bucket does not exist. Creating bucket $S3_BUCKET..."
        try {
            aws s3 mb "s3://$S3_BUCKET" --region $AWS_REGION --profile $AWS_CLI_PROFILE
            Write-Message "success" "S3 bucket created successfully."
            $S3_BUCKET_CREATED = $true
        } catch {
            Write-Message "error" "Failed to create S3 bucket: $_"
            exit 1
        }
    }

    Write-Message "info" "Configuring bucket for static website hosting..."
    try {
        aws s3 website "s3://$S3_BUCKET" --index-document index.html --error-document index.html --profile $AWS_CLI_PROFILE
        Write-Message "info" "Setting bucket policy for public read access..."
        $BucketPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$S3_BUCKET/*"
        }
    ]
}
"@

        $PolicyFile = "bucket-policy.json"
        $BucketPolicy | Out-File -FilePath $PolicyFile -Encoding utf8

        aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file://$PolicyFile --profile $AWS_CLI_PROFILE
        Remove-Item $PolicyFile

        Write-Message "success" "S3 bucket configured successfully for static website hosting."
    } catch {
        Write-Message "error" "Failed to configure S3 bucket: $_"
        exit 1
    }
}

# Function to check existing resources
function Check-ExistingResources {
    Write-Message "info" "Checking existing resources..."

    # Check S3 bucket
    try {
        aws s3 ls "s3://$S3_BUCKET" --profile $AWS_CLI_PROFILE >$null
        $S3_EXISTS = $true
        Write-Message "info" "S3 bucket already exists: $S3_BUCKET"
    } catch {
        $S3_EXISTS = $false
    }

    # Check CloudFront distribution
    $DistributionId = aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0] == '$DOMAIN_NAME'].Id" --output text --profile $AWS_CLI_PROFILE
    if ([string]::IsNullOrEmpty($DistributionId) -or $DistributionId -eq "None") {
        $CF_EXISTS = $false
    } else {
        $CF_EXISTS = $true
        Write-Message "info" "CloudFront distribution already exists: $DistributionId"
    }

    # Check SSL certificate
    $CertArn = aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text --profile $AWS_CLI_PROFILE
    if ([string]::IsNullOrEmpty($CertArn) -or $CertArn -eq "None") {
        $CERT_EXISTS = $false
    } else {
        $CERT_EXISTS = $true
        $CERTIFICATE_ARN = $CertArn
        $CERT_VALID = Validate-SslCertificate
    }

    # Check Route 53 hosted zone
    if ($DNS_METHOD -eq "route53") {
        $HostedZoneId = aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --query "HostedZones[0].Id" --output text --profile $AWS_CLI_PROFILE
        if ([string]::IsNullOrEmpty($HostedZoneId) -or $HostedZoneId -eq "None") {
            $R53_EXISTS = $false
        } else {
            $R53_EXISTS = $true
            $HOSTED_ZONE_ID = $HostedZoneId
            Write-Message "info" "Route 53 hosted zone already exists: $HOSTED_ZONE_ID"
        }
    }
}

# Main execution flow
try {
    Write-Message "info" "Starting deployment process..."

    # Load configuration
    Load-Configuration

    # Check if AWS CLI is installed and configured correctly
    if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
        Write-Message "warning" "AWS CLI is not installed."
        $reply = Read-Host "Do you want to attempt to install AWS CLI? (y/n)"
        if ($reply -match '^[Yy]$') {
            Write-Message "info" "Installing AWS CLI..."
            Install-AwsCli
            if (Get-Command "aws" -ErrorAction SilentlyContinue) {
                Write-Message "success" "AWS CLI installed successfully."
            } else {
                Write-Message "error" "AWS CLI installation failed. Please install it manually."
                exit 1
            }
        } else {
            Write-Message "error" "Please install AWS CLI manually and run this script again."
            exit 1
        }
    }

    Check-AwsCliConfig
    Validate-AwsConfig

    # Validate environment variables and set S3_BUCKET
    Validate-EnvVariables

    # Validate S3 bucket name
    if (-not (Validate-BucketName $S3_BUCKET)) {
        Write-Message "error" "Invalid S3 bucket name. Please correct it in the .env file."
        exit 1
    }

    # Check existing resources
    Check-ExistingResources

    # Create and configure S3 bucket (if it doesn't exist)
    if (-not $S3_EXISTS) {
        Write-Message "info" "Creating and configuring S3 bucket..."
        Create-AndConfigureS3Bucket
    } else {
        Write-Message "info" "Using existing S3 bucket..."
        Check-S3Permissions
    }

    # Build the React app
    Build-ReactApp

    $script:deploymentComplete = $true
    $script:deploymentPaused = $false

    # Request and validate certificate
    if (-not $CERT_EXISTS -or -not $CERT_VALID) {
        $certStatus = Request-AndValidateCertificate
        $CERTIFICATE_CREATED = $true
    } else {
        Write-Message "info" "Using existing valid SSL certificate..."
    }

    # Only continue with the rest of the deployment if the certificate is ready
    if ($deploymentComplete) {
        # Create or get CloudFront distribution
        if (-not $CF_EXISTS) {
            Write-Message "info" "Setting up CloudFront distribution..."
            Create-OrGetCloudFrontDistribution
            $CLOUDFRONT_DISTRIBUTION_CREATED = $true
        } else {
            Write-Message "info" "Using existing CloudFront distribution..."
            Validate-CloudFrontDistribution
        }

        # Invalidate CloudFront cache
        Write-Message "info" "Initiating CloudFront cache invalidation..."
        $InvalidationId = aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_DISTRIBUTION_ID --paths "/*" --query 'Invalidation.Id' --output text --profile $AWS_CLI_PROFILE

        if ($InvalidationId) {
            Write-Message "success" "CloudFront invalidation initiated. ID: $InvalidationId"
            Write-Message "info" "The invalidation process has started but may take up to 15 minutes to complete."
            Write-Message "info" "Your updated content may be available sooner, but full propagation can take some time."
            Write-Message "info" "You can check the status of the invalidation in the AWS CloudFront console."
        } else {
            Write-Message "warning" "Failed to initiate CloudFront invalidation. You may need to invalidate the cache manually."
        }

        Write-Message "info" "Continuing with the deployment process..."

        # Handle DNS updates
        if ($DNS_METHOD -eq "route53") {
            Create-OrGetHostedZoneAndCheckNameservers
            $reply = Read-Host "Do you want to update DNS using Route 53? (y/n)"
            if ($reply -match '^[Yy]$') {
                Update-Route53Dns
            } else {
                Write-Message "warning" "Skipping Route 53 DNS update."
            }
        } elseif ($DNS_METHOD -eq "manual") {
            Write-Message "info" "Manual DNS configuration selected."
            Provide-ManualDnsInfo
        } else {
            Write-Message "error" "Invalid DNS_METHOD in .env file. Please set it to either 'route53' or 'manual'."
            exit 1
        }

        # Check DNS propagation
        Check-DnsPropagation

        # Deployment summary
        Write-Message "success" "Deployment process completed."
        Write-Host ""
        Write-Message "info" "Deployment Summary:"
        Write-Host "  • S3 Bucket: $S3_BUCKET"
        Write-Host "  • CloudFront Distribution: $CLOUDFRONT_DISTRIBUTION_ID"
        Write-Host "  • Domain: $DOMAIN_NAME"
        Write-Host "  • SSL Certificate ARN: $CERTIFICATE_ARN"

        if ($CF_EXISTS) {
            Write-Host ""
            Write-Message "success" "Your updated website should be accessible at https://$DOMAIN_NAME"
            Write-Host "Note: It may take a few minutes for changes to propagate through CloudFront."
        } elseif ($DNS_METHOD -eq "manual") {
            Write-Host ""
            Write-Message "warning" "Next Steps:"
            Write-Host "  1. Update your DNS records as instructed (if not already done)."
            Write-Host "  2. Wait for DNS propagation (up to 48 hours)."
            Write-Host "  3. Your website will be accessible at https://$DOMAIN_NAME"
        } else {
            Write-Host ""
            Write-Message "success" "Your website should be accessible at https://$DOMAIN_NAME"
            Write-Host "Note: It may take a few minutes for changes to propagate."
        }

        Write-Message "success" "Deployment completed successfully."
    } else {
        Write-Message "info" "Partial deployment completed. Please run the script again after DNS propagation to complete the process."
    }

} catch {
    # Handle any errors
    Write-Message "error" "An error occurred during deployment: $_"
    $script:deploymentComplete = $false
    $script:deploymentPaused = $false
} finally {
    # Stop logging
    Stop-Transcript

    if ($deploymentPaused) {
        Write-Message "info" "Deployment paused for manual steps. No rollback necessary."
        Write-Message "info" "Please run the script again after completing the manual DNS configuration."
    } elseif ($deploymentComplete) {
        Write-Message "success" "Deployment completed successfully."
    } elseif (-not $deploymentComplete -and -not $deploymentPaused) {
        Rollback
    }
}

Write-Host "Current working directory: $PWD"
Write-Host "Script location: $PSScriptRoot"
Write-Host "AWS_REGION is set to: $AWS_REGION"
Write-Host "AWS_CLI_PROFILE is set to: $AWS_CLI_PROFILE"
Write-Host "DOMAIN_NAME is set to: $DOMAIN_NAME"
Write-Host "DNS_METHOD is set to: $DNS_METHOD"
Write-Host "CERTIFICATE_ARN is set to: $CERTIFICATE_ARN"