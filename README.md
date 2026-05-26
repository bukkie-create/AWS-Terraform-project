# AWS Terraform Project

## Overview
This project provisions AWS infrastructure using Terraform.

## AWS Services Used
- AWS Lambda
- Amazon SQS
- Amazon SNS
- CloudWatch Logs
- AWS KMS

## Features
- Infrastructure as Code using Terraform
- Encrypted SQS queue using KMS
- Lambda log groups
- SNS topic integration
- Terraform variables and outputs

## Project Structure
```bash
main.tf
variables.tf
outputs.tf
lambda/index.py
```

## Terraform Commands
```bash
terraform init
terraform plan
terraform apply
```

## Deployment Verification
Resources verified in AWS Console:
- Lambda functions
- SQS queue
- SNS topic
- CloudWatch log groups

## Author
Bukola Komolafe