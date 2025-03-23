# Jenkins + AWS ECS CI/CD Demo

This project demonstrates a simple CI/CD pipeline using Jenkins to build and deploy a Python Flask application to AWS ECS (Fargate). The infrastructure is fully managed using Terraform, including VPC, EC2 (for Jenkins), ECR, ALB, and ECS.

## Project Structure

```
├── app.py               # Flask web application
├── requirements.txt     # Python dependencies
├── Dockerfile           # Docker image for the Flask app
├── Jenkinsfile          # Jenkins pipeline script
├── main.tf              # Terraform infrastructure definition
├── output.tf            # Terraform outputs
```

## Architecture Overview

The project includes:

- Terraform-managed AWS infrastructure:
  - VPC, Subnets, and Security Groups
  - Jenkins EC2 with EIP
  - Application Load Balancer (ALB)
  - ECS Cluster, Task, and Fargate Service
  - ECR repository for Docker image

- Jenkins CI/CD pipeline:
  - Clone source code from GitHub
  - Build stage (placeholder for Docker build)
  - Test stage (placeholder for test logic)
  - Deploy stage (to be implemented: push image and redeploy ECS service)

## Getting Started

### Prerequisites

- Terraform
- AWS CLI
- Docker

### Deploy Infrastructure with Terraform

```bash
terraform init
terraform apply
```

After deployment, Terraform will output:

- Jenkins EC2 public IP
- ALB DNS name
- ECR repository URL

## IAM Roles and Permissions

- Jenkins EC2 instance:
  - AmazonEC2ContainerRegistryFullAccess
  - AmazonECS_FullAccess

- ECS Task Execution Role:
  - AmazonECSTaskExecutionRolePolicy


## Possible Improvements

- Implement Docker build and push in Jenkins Deploy stage
- Add Slack or email notifications
- Implement ECS Blue/Green deployments
- Add GitHub webhook trigger

## Author

By @jasontsaicc — Jenkins + ECS deployment practice project.
