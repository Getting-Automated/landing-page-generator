#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Ensure that all parts of a pipeline are checked for errors

# AWS configuration
AWS_REGION="us-east-1"
LAMBDA_FUNCTION_NAME="workflowsy-contact-form-handler"
SENDER_EMAIL="hunter@workflowsy.io"
OWNER_EMAIL="hunter@workflowsy.io"

# Disable the AWS CLI pager
export AWS_PAGER=""

# IAM role configuration
ROLE_NAME="workflowsy-lambda-role"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

# Check if IAM role exists
if aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" 2>&1 | grep -q "NoSuchEntity"; then
    echo "Creating IAM role..."
    ROLE_RESPONSE=$(aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        }
      }]
    }' --region "$AWS_REGION")
    LAMBDA_ROLE_ARN=$(echo "$ROLE_RESPONSE" | jq -r '.Role.Arn')

    # Attach policy to the role
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" --region "$AWS_REGION"

    # Wait for role to propagate
    echo "Waiting for IAM role to propagate..."
    sleep 10
else
    echo "IAM role already exists. Skipping creation."
    LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --region "$AWS_REGION" | jq -r '.Role.Arn')
fi

# Create a temporary directory for packaging
mkdir -p temp_lambda_package
cp lambda_handler.py owner_template.html submitter_template.html temp_lambda_package/

# Create deployment package
cd temp_lambda_package
zip -r ../lambda_function.zip .
cd ..

# CORS configuration
CORS_CONFIG=$(cat <<EOF
{
  "Cors": {
    "AllowOrigins": ["*"],
    "AllowMethods": ["POST"],
    "AllowHeaders": ["Content-Type"],
    "ExposeHeaders": ["*"],
    "MaxAge": 86400
  }
}
EOF
)

# Validate the CORS configuration
echo "CORS Configuration:"
echo "$CORS_CONFIG" | jq .

# Function to create or update function URL
function manage_function_url {
    local action=$1
    local cmd="aws lambda $action-function-url-config \
        --function-name $LAMBDA_FUNCTION_NAME \
        --auth-type NONE \
        --region $AWS_REGION \
        --cli-input-json '$CORS_CONFIG' \
        --no-cli-pager"
    
    echo "Executing: $cmd"
    eval $cmd
}

# Check if the Lambda function exists
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>&1 | grep -q "Function not found"; then
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_handler.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --region "$AWS_REGION"

    echo "Lambda function '$LAMBDA_FUNCTION_NAME' created successfully."

    echo "Creating Function URL..."
    manage_function_url "create"
else
    # Update Lambda function code
    aws lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file fileb://lambda_function.zip \
        --region "$AWS_REGION"

    echo "Lambda function '$LAMBDA_FUNCTION_NAME' code updated successfully."

    # Check if function URL exists
    if aws lambda get-function-url-config --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>&1 | grep -q "ResourceNotFoundException"; then
        echo "Function URL does not exist. Creating..."
        manage_function_url "create"
    else
        echo "Function URL exists. Updating configuration..."
        manage_function_url "update"
    fi
fi

# Retrieve the Function URL
FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --query "FunctionUrl" --output text)
echo "Function URL: $FUNCTION_URL"

# Update Lambda function configuration (environment variables)
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --environment "Variables={SENDER_EMAIL=$SENDER_EMAIL,OWNER_EMAIL=$OWNER_EMAIL}" \
    --region "$AWS_REGION"

echo "Environment variables updated for Lambda function '$LAMBDA_FUNCTION_NAME'."

# Clean up
rm -rf temp_lambda_package
rm lambda_function.zip

echo "Deployment completed successfully."
