# Coffee Shop Application Deployment on AWS

## Table of Contents

1.  [Summary](#summary)
2.  [Architecture](#architecture)
    *   [Development Environment Architecture](#development-environment-architecture)
    *   [Production Environment Architecture](#production-environment-architecture)
3.  [Component Description](#component-description)
    *   [AWS Services Used](#aws-services-used)
    *   [Application Services](#application-services)
    *   [Tools and Technologies](#tools-and-technologies)
4.  [Application Homepage](#application-homepage)
5.  [User Guideline](#user-guideline)
    *   [Prerequisites](#prerequisites)
    *   [Infrastructure Provisioning (Terraform)](#infrastructure-provisioning-terraform)
        *   [Backend Configuration](#backend-configuration)
        *   [Common Infrastructure](#common-infrastructure)
        *   [Development Environment Infrastructure](#development-environment-infrastructure)
        *   [Production Environment Infrastructure (RDS & EKS)](#production-environment-infrastructure-rds--eks)
    *   [Preparing Docker Images (Push to ECR)](#preparing-docker-images-push-to-ecr)
    *   [Deploying to Development Environment (EC2 + Docker Compose)](#deploying-to-development-environment-ec2--docker-compose)
    *   [Deploying to Production Environment (EKS)](#deploying-to-production-environment-eks)
        *   [Connecting kubectl to EKS](#connecting-kubectl-to-eks)
        *   [Setting up Secrets (AWS Secrets Manager & CSI Driver)](#setting-up-secrets-aws-secrets-manager--csi-driver)
        *   [Applying Kubernetes Manifests](#applying-kubernetes-manifests)
        *   [Setting up AWS Load Balancer Controller](#setting-up-aws-load-balancer-controller)
        *   [Setting up Horizontal Pod Autoscaler (HPA)](#setting-up-horizontal-pod-autoscaler-hpa)
    *   [CI/CD Pipeline](#cicd-pipeline)
    *   [Monitoring System](#monitoring-system)
    *   [Cleaning Up Resources](#cleaning-up-resources)

---

## 1. Summary

This project demonstrates the deployment of a microservices-based "Coffee Shop" application onto Amazon Web Services (AWS). The solution encompasses Infrastructure as Code (IaC) using Terraform, containerization with Docker, orchestration with Kubernetes (Amazon EKS) for production, and a simpler Docker Compose setup on EC2 for development.

Key features include:
*   Separate Development and Production environments.
*   Infrastructure provisioned and managed by Terraform with an S3 backend and distinct workspaces.
*   Application images stored in Amazon Elastic Container Registry (ECR).
*   Production database hosted on Amazon RDS for PostgreSQL, with credentials managed by AWS Secrets Manager.
*   Security considerations for data at rest and in transit.
*   Horizontal Pod Autoscaling for the production environment.

---

## 2. Architecture


### Development Environment Architecture

*   **Compute:** Single Amazon EC2 instance.
*   **Containerization:** Docker and Docker Compose.
*   **Services:** All application services (web, proxy, product, counter, barista, kitchen), PostgreSQL, and RabbitMQ run as Docker containers on the EC2 instance.
*   **Networking:** EC2 Security Group allows traffic on necessary ports (SSH, application ports).
*   **ECR:** Images are pulled from ECR.
<!-- Diagram -->
```
+---------------------------------+
| Development EC2 Instance |
| (Docker & Docker Compose) |
| |
| +---------------------------+ |
| | Docker Network | |
| | | |
| | +---------------------+ | |
| | | go-coffeeshop-web | | | <-- Port 8888 (Public)
| | +---------------------+ | |
| | | go-coffeeshop-proxy | | | <-- Port 5000
| | +---------------------+ | |
| | | ... other app svcs | | |
| | +---------------------+ | |
| | | PostgreSQL Container| | |
| | +---------------------+ | |
| | | RabbitMQ Container | | |
| | +---------------------+ | |
| +---------------------------+ |
| |
+---------------------------------+
^
| Pulls Images
|
+---------------------------------+
| Amazon ECR |
+---------------------------------+
```
### Production Environment Architecture

*   **Compute & Orchestration:** Amazon EKS (Elastic Kubernetes Service) with a managed node group.
*   **Containerization:** Docker images run as Kubernetes Pods.
*   **Database:** Amazon RDS for PostgreSQL (Free-tier, t3.micro, no HA, no read-replica).
*   **Messaging:** RabbitMQ deployed within EKS (or using Amazon MQ if preferred).
*   **Secrets Management:** AWS Secrets Manager integrated with EKS using the Secrets Store CSI Driver.
*   **Networking:**
    *   AWS VPC with public and private subnets.
    *   EKS cluster and worker nodes in private subnets.
    *   RDS in private subnets.
    *   AWS Load Balancer Controller for exposing services (e.g., `go-coffeeshop-web` via an Application LoadBalancer).
    *   Security Groups for EKS nodes, RDS, and Load Balancers.
*   **Scalability:** Horizontal Pod Autoscaler (HPA) for frontend/critical services.
*   **ECR:** Images are pulled from ECR.

<!-- Expected Diagram -->
```
+---------------------------------------------------------------------------------+
| AWS Cloud |
| +-----------------------------------------------------------------------------+ |
| | VPC (e.g., 10.0.0.0/16) | |
| | | |
| | +---------------------+ +------------------------------------------------+ | |
| | | Public Subnets | | Private Subnets | | |
| | | +---------------+ | | +--------------------------------------------+ | | |
| | | | NAT Gateway(s)| | | | EKS Control Plane (Managed by AWS) | | | |
| | | +---------------+ | | +--------------------------------------------+ | | |
| | | | | | | |
| | | +---------------+ | | +--------------------------------------------+ | | |
| | | | ALB |<--+--+->| EKS Worker Nodes (Managed Node Group) | | | |
| | | +---------------+ | | | +---------------------------------------+ | | | |
| | | ^ | | | | K8s Pods: | | | | |
| | | | Internet | | | | - go-coffeeshop-web (HPA) | | | | |
| | +--------+------------+ | | | - go-coffeeshop-proxy | | | | |
| | | | | - ... other app services | | | | |
| | | | | - RabbitMQ (if in EKS) | | | | |
| | | | +---------------------------------------+ | | | |
| | | | (Secrets via CSI Driver from Secrets Manager) | | | |
| | | +--------------------------------------------+ | | |
| | | | | |
| | | +--------------------------------------------+ | | |
| | | | Amazon RDS for PostgreSQL (t3.micro) | | | |
| | | +--------------------------------------------+ | | |
| | +------------------------------------------------+ | |
| +-----------------------------------------------------------------------------+ |
| |
| +----------------------+ +----------------------+ +-------------------------+ |
| | AWS Secrets Manager | | Amazon ECR | | Amazon CloudWatch | |
| | (DB Credentials etc.)| | (Docker Images) | | (Logs, Metrics, Alarms) | |
| +----------------------+ +----------------------+ +-------------------------+ |
| |
| +-----------------------------------------------------------------------------+ |
| | CI/CD Pipeline (e.g., GitHub Actions) | |
| | Scan (Trivy) -> Push to ECR -> Deploy to EKS (ArgoCD/Helm/kubectl) | |
| +-----------------------------------------------------------------------------+ |
+---------------------------------------------------------------------------------+
```

## 3. Component Description

### AWS Services Used

*   **Amazon EC2 (Elastic Compute Cloud):** Hosts the development environment and potentially CI/CD tools like self-hosted TeamCity/ArgoCD.
*   **Amazon EKS (Elastic Kubernetes Service):** Manages the production Kubernetes cluster for orchestrating application containers.
*   **Amazon RDS (Relational Database Service):** Provides a managed PostgreSQL database for the production environment.
*   **Amazon ECR (Elastic Container Registry):** Stores Docker images for the application.
*   **AWS Secrets Manager:** Securely stores and manages sensitive data like database credentials.
*   **Amazon S3 (Simple Storage Service):** Used as a remote backend for Terraform state files.
*   **Amazon VPC (Virtual Private Cloud):** Provides network isolation for resources. Includes Subnets, Route Tables, Internet Gateway, NAT Gateways.
*   **AWS IAM (Identity and Access Management):** Manages access to AWS services and resources using roles and policies.
*   **AWS Load Balancer Controller (for EKS):** Provisions Application Load Balancers (ALB) to expose services running in EKS.
*   **Amazon CloudWatch:** <!-- TODO: Confirm if this is the chosen tool --> Used for collecting logs, metrics, creating dashboards, and setting up alarms for monitoring.
*   **AWS CodePipeline / AWS CodeBuild / AWS CodeDeploy:** <!-- TODO: If using AWS native CI/CD --> Components for the CI/CD pipeline.
*   **DynamoDB:** Used for Terraform state locking.

### Application Services

The application consists of the following microservices (images pulled from `cuongopswat` on Docker Hub and pushed to private ECR):

*   **`cuongopswat/go-coffeeshop-web`:** The frontend web interface.
    *   `REVERSE_PROXY_URL`: Points to the proxy service.
    *   `WEB_PORT`: `8888`.
*   **`cuongopswat/go-coffeeshop-proxy`:** Acts as a gRPC proxy/aggregator for backend services.
    *   Connects to `product` and `counter` services.
*   **`cuongopswat/go-coffeeshop-barista`:** Handles order preparation logic related to drinks.
    *   Requires PostgreSQL and RabbitMQ.
*   **`cuongopswat/go-coffeeshop-kitchen`:** Handles order preparation logic related to food.
    *   Requires PostgreSQL and RabbitMQ.
*   **`cuongopswat/go-coffeeshop-counter`:** Manages orders and interacts with the product service.
    *   Requires PostgreSQL, RabbitMQ, and `product` service.
*   **`cuongopswat/go-coffeeshop-product`:** Manages product information.
*   **`postgres:14-alpine`:** Database for application data.
*   **`rabbitmq:3.11-management-alpine`:** Message broker for asynchronous communication between services.

**Service Startup Order:**
1.  PostgreSQL
2.  RabbitMQ
3.  Product
4.  Counter
5.  Remaining services (Barista, Kitchen, Proxy, Web)

**Exposed Ports (Default):**
*   PostgreSQL: `5432`
*   RabbitMQ: `5672` (AMQP), `15672` (Management UI)
*   Proxy: `5000`
*   Product: `5001`
*   Counter: `5002`
*   Web: `8888`

### Tools and Technologies

*   **Terraform:** Infrastructure as Code.
*   **Docker & Docker Compose:** Containerization and local/dev orchestration.
*   **Kubernetes (kubectl):** Container orchestration for production.
*   **AWS CLI:** Command-line interface for AWS.
*   **Git:** Version control.

---

## 4. The homepage of the application


You can access the application homepage (once deployed to production) via the URL provided by the Application Load Balancer. This URL will be an output of the EKS deployment or can be found in the AWS console under EC2 > Load Balancers.

For the development environment, it's accessible via `http://<DEV_EC2_PUBLIC_IP>:8888`.

---

## 5. User Guideline

### Prerequisites

*   AWS Account with necessary permissions.
*   AWS CLI installed and configured (`aws configure`).
*   Terraform installed.
*   Docker & Docker Compose installed.
*   kubectl installed.
*   Git installed.
*   A Git client configured for your chosen VCS (e.g., GitHub).

### Infrastructure Provisioning (Terraform)

The Terraform code is organized into a root directory and environment-specific directories (`dev`, `prod`).
