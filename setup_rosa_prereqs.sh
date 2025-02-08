#!/bin/bash

set -e  # Exit immediately if a command fails

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NOC='\033[0m'

echo -e "${GREEN}ROSA Prerequisites Setup Script${NOC}"

# Step 1: Download and install the ROSA CLI
echo -e "${GREEN}Step 1: Installing ROSA CLI...${NOC}"

ROSA_URL="https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz"
TMP_DIR=$(mktemp -d)
ROSA_ARCHIVE="$TMP_DIR/rosa-linux.tar.gz"

# Download and extract ROSA CLI
curl -L $ROSA_URL -o $ROSA_ARCHIVE
tar -xzf $ROSA_ARCHIVE -C $TMP_DIR
sudo mv $TMP_DIR/rosa /usr/local/bin/
rm -rf $TMP_DIR

# Verify installation
if command -v rosa &> /dev/null; then
    echo -e "${GREEN}ROSA CLI installed successfully.${NOC}"
else
    echo -e "${RED}ROSA CLI installation failed.${NOC}"
    exit 1
fi

# Step 1.2: Check and Install AWS CLI
echo -e "${GREEN}Step 1.2: Checking AWS CLI installation...${NOC}"

if ! command -v aws &> /dev/null; then
    echo -e "${GREEN}AWS CLI not found. Installing AWS CLI...${NOC}"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    sudo apt update && sudo apt install -y unzip
    unzip /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip

    # Verify installation
    if command -v aws &> /dev/null; then
        echo -e "${GREEN}AWS CLI installed successfully.${NOC}"
    else
        echo -e "${RED}AWS CLI installation failed.${NOC}"
        exit 1
    fi
else
    echo -e "${GREEN}AWS CLI is already installed.${NOC}"
fi

# Step 1.3: Configure AWS CLI (Check credentials and region)
echo -e "${GREEN}Step 1.3: Checking AWS CLI Configuration...${NOC}"

AWS_CONFIGURED=1  # Assume AWS is already configured

# Check if AWS credentials are set
if ! aws configure get aws_access_key_id &> /dev/null; then
    echo -e "${RED}AWS credentials not found. Please enter your AWS credentials.${NOC}"
    aws configure
    AWS_CONFIGURED=0  # Mark as newly configured
else
    echo -e "${GREEN}AWS credentials are already configured.${NOC}"
fi

# Check if AWS region is set
if ! aws configure get region &> /dev/null; then
    read -p "Enter your AWS region (e.g., us-east-1): " AWS_REGION
    aws configure set region "$AWS_REGION"
    AWS_CONFIGURED=0  # Mark as newly configured
else
    AWS_REGION=$(aws configure get region)
    echo -e "${GREEN}AWS region is already set to: $AWS_REGION${NOC}"
fi

if [[ "$AWS_CONFIGURED" -eq 0 ]]; then
    echo -e "${GREEN}AWS CLI is now fully configured.${NOC}"
else
    echo -e "${GREEN}AWS CLI was already configured, skipping setup.${NOC}"
fi

# Step 2: Log in to ROSA CLI
echo -e "${GREEN}Step 2: Logging in to ROSA...${NOC}"
read -s -p "Enter your ROSA login token: " ROSA_TOKEN
echo ""  # Move to a new line

rosa login --token="$ROSA_TOKEN"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}ROSA login successful.${NOC}"
else
    echo -e "${RED}ROSA login failed. Please check your token and try again.${NOC}"
    exit 1
fi

# Step 2.2: Create AWS account roles and policies
echo -e "${GREEN}Step 2.2: Creating AWS account roles and policies...${NOC}"

rosa create account-roles --mode auto

if [ $? -eq 0 ]; then
    echo -e "${GREEN}AWS account roles and policies created successfully.${NOC}"
else
    echo -e "${RED}Failed to create AWS account roles and policies.${NOC}"
    exit 1
fi

# Step 3: Create a Virtual Private Network (VPC) (Only for ROSA HCP clusters)
read -p "Are you setting up a ROSA HCP cluster? (y/n): " CREATE_VPC

if [[ "$CREATE_VPC" == "y" || "$CREATE_VPC" == "Y" ]]; then
    echo -e "${GREEN}Step 3: Creating Virtual Private Network (VPC)...${NOC}"
    
    rosa create network

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}VPC and networking components created successfully.${NOC}"
    else
        echo -e "${RED}Failed to create VPC. Please check the logs.${NOC}"
        exit 1
    fi
fi

echo -e "${GREEN}ROSA prerequisites setup completed successfully!${NOC}"

rosa create oidc-config -h
rosa create cluster

