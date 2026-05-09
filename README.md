# Solomon App — Production-Ready Deployment on AWS EKS

A simple static web application containerized with Docker and deployed to AWS EKS via a fully automated Jenkins CI/CD pipeline, with infrastructure provisioned using Terraform.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring & Logging](#monitoring--logging)
- [Design Decisions](#design-decisions)
- [Assumptions](#assumptions)
- [Limitations & Improvements](#limitations--improvements)

---

## Architecture Overview

```
Developer (git push)
        │
        ▼
  GitHub Repository
        │
        ▼
  Jenkins (EC2 t3.medium)
  ┌─────────────────────┐
  │ 1. Checkout         │
  │ 2. Docker Build     │
  │ 3. Smoke Test       │
  │ 4. Push to ECR      │
  │ 5. Deploy to EKS    │
  └─────────────────────┘
        │
        ▼
  Amazon ECR
  (Docker Image Registry)
        │
        ▼
  Amazon EKS Cluster — DEMO_CLUSTER
  ┌──────────────────────────────┐
  │  Namespace: solomon-ns       │
  │  Deployment: 2 replicas      │
  │  (Nginx serving index.html)  │
  └──────────────────────────────┘
        │
        ▼
  AWS LoadBalancer (ELB)
        │
        ▼
     Browser
```

### Infrastructure Components

| Component        | Service              | Purpose                                      |
|------------------|----------------------|----------------------------------------------|
| Networking       | AWS VPC              | Isolated network with 2 public subnets       |
| Container Registry | Amazon ECR         | Stores versioned Docker images               |
| Orchestration    | Amazon EKS (K8s 1.35)| Runs and manages application containers      |
| CI/CD Server     | Jenkins on EC2       | Automates build, test, and deploy            |
| Monitoring       | AWS CloudWatch       | Logs from EKS control plane and nodes        |
| IaC              | Terraform >= 1.3     | Provisions all AWS infrastructure            |

---

## Project Structure

```
├── app/
│   └── index.html              # Static web application
├── docker/
│   └── Dockerfile              # Nginx-based container definition
├── k8s/
│   ├── namespace.yaml          # Kubernetes namespace (solomon-ns)
│   ├── deployment.yaml         # Deployment with 2 replicas
│   └── service.yaml            # LoadBalancer service
├── terraform/
│   ├── main.tf                 # Provider config and backend
│   ├── variables.tf            # All configurable variables
│   ├── vpc.tf                  # VPC, subnets, internet gateway
│   ├── eks.tf                  # EKS cluster, node group, IAM roles
│   ├── ecr.tf                  # ECR repository and lifecycle policy
│   ├── jenkins-ec2.tf          # Jenkins EC2, IAM role, security group
│   └── outputs.tf              # Useful outputs after apply
├── Jenkinsfile                 # Declarative CI/CD pipeline
└── README.md
```

---

## Prerequisites

Ensure the following are installed and configured on your **local machine** before deploying:

| Tool        | Version     | Purpose                          |
|-------------|-------------|----------------------------------|
| Terraform   | >= 1.3.0    | Provision AWS infrastructure     |
| AWS CLI     | >= 2.0      | Authenticate with AWS            |
| kubectl     | >= 1.35     | Interact with EKS cluster        |
| Git         | Any         | Push code to GitHub              |

You also need:
- An **AWS account** with programmatic access configured (`aws configure`)
- An **EC2 Key Pair** created in your AWS account (used for SSH into Jenkins)
- A **GitHub repository** with this project pushed to the `main` branch

---

## Deployment Steps

### 1. Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region (us-east-1), output format (json)
```

### 2. Create an EC2 Key Pair (for Jenkins SSH access)

```bash
aws ec2 create-key-pair \
  --key-name solomon-key \
  --query 'KeyMaterial' \
  --output text > solomon-key.pem

chmod 400 solomon-key.pem
```

### 3. Provision Infrastructure with Terraform

```bash
cd terraform

# Initialise Terraform and download providers
terraform init

# Preview what will be created
terraform plan

# Provision all infrastructure (~15 minutes for EKS)
terraform apply
```

After apply completes, note the outputs:

```
jenkins_url         = "http://<PUBLIC_IP>:8080"
ecr_repository_url  = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/solomon-app"
eks_cluster_name    = "DEMO_CLUSTER"
aws_account_id      = "<YOUR_ACCOUNT_ID>"
```

### 4. Configure Jenkins

**a. Unlock Jenkins**

SSH into the Jenkins EC2:
```bash
ssh -i solomon-key.pem ec2-user@<JENKINS_PUBLIC_IP>
```

Get the initial admin password:
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open `http://<JENKINS_PUBLIC_IP>:8080` in your browser, paste the password, and install suggested plugins.

**b. Add AWS Account ID Credential**

Go to **Manage Jenkins → Credentials → Global → Add Credential**:
- Kind: `Secret text`
- Secret: your 12-digit AWS Account ID
- ID: `aws-account-id`

**c. Create the Pipeline Job**

1. Click **New Item → Pipeline**
2. Name it `solomon-app`
3. Under **Pipeline**, select **Pipeline script from SCM**
4. SCM: **Git**
5. Repository URL: your GitHub repo URL
6. Branch: `*/main`
7. Script Path: `Jenkinsfile`
8. Click **Save**

### 5. Grant Jenkins Access to EKS

On the Jenkins EC2, update the EKS `aws-auth` ConfigMap to allow the Jenkins IAM role to deploy:

```bash
# On your local machine (where kubectl is configured)
aws eks update-kubeconfig --region us-east-1 --name DEMO_CLUSTER

kubectl edit configmap aws-auth -n kube-system
```

Add the following under `mapRoles`:

```yaml
- rolearn: arn:aws:iam::<ACCOUNT_ID>:role/solomon-app-jenkins-role
  username: jenkins
  groups:
    - system:masters
```

### 6. Run the Pipeline

In Jenkins, click **Build Now** on the `solomon-app` pipeline.

The pipeline will:
1. Pull code from GitHub
2. Build the Docker image
3. Run a smoke test
4. Push the image to ECR
5. Deploy to EKS

### 7. Access the Application

After the pipeline succeeds, get the LoadBalancer URL:

```bash
kubectl get svc solomon-app-svc -n solomon-ns
```

Open the `EXTERNAL-IP` value in your browser. Note: it may take 2–3 minutes for the ELB to become active.

---

## CI/CD Pipeline

The `Jenkinsfile` defines a declarative pipeline with 5 stages:

| Stage         | Description                                                              |
|---------------|--------------------------------------------------------------------------|
| Checkout      | Pulls latest code from GitHub                                            |
| Build         | Builds Docker image tagged with Jenkins `BUILD_NUMBER` and `latest`      |
| Test          | Runs container locally, asserts HTTP 200 and expected page content       |
| Push to ECR   | Authenticates via IAM role and pushes both image tags to ECR             |
| Deploy to EKS | Updates kubeconfig, applies K8s manifests, waits for rollout to complete |

Every build is tagged with the Jenkins build number, enabling rollback to any previous version:

```bash
# Rollback example
kubectl set image deployment/solomon-app \
  solomon-app=<ECR_URL>/solomon-app:<PREVIOUS_BUILD_NUMBER> \
  -n solomon-ns
```

---

## Monitoring & Logging

### EKS Control Plane Logs
Enabled via Terraform — logs for `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler` are streamed to **AWS CloudWatch** under:
```
/aws/eks/DEMO_CLUSTER/cluster
```

### Application Logs
View live pod logs:
```bash
kubectl logs -l app=solomon-app -n solomon-ns --follow
```

### CloudWatch Container Insights (optional enhancement)
Can be enabled on the EKS cluster to get CPU, memory, and network metrics per pod in CloudWatch dashboards.

---

## Design Decisions

**Why EKS over ECS or EC2?**
EKS provides a production-grade Kubernetes environment with built-in self-healing, rolling deployments, and horizontal scaling. It reflects real-world enterprise usage and demonstrates Kubernetes proficiency.

**Why Jenkins over GitHub Actions?**
Jenkins was specified as the preferred CI/CD tool. Running Jenkins on EC2 within the same VPC as EKS keeps network latency low and avoids exposing the cluster API to external CI runners.

**Why a LoadBalancer service over Ingress?**
For a single-service deployment, a LoadBalancer service is the simplest and most direct way to expose the app externally on AWS. An Ingress controller (e.g. ALB Ingress Controller) would add value for multi-service routing but introduces unnecessary complexity here.

**Why public subnets only?**
For simplicity and cost — private subnets require NAT Gateways (~$32/month each). For a real production system, worker nodes would sit in private subnets with NAT Gateways for outbound traffic.

**Why IAM roles over stored credentials?**
The Jenkins EC2 instance uses an IAM instance profile to authenticate with ECR and EKS. This avoids storing AWS credentials in Jenkins or environment variables, which is a security best practice.

**Why image tagging with BUILD_NUMBER?**
Each build produces a uniquely tagged image. This makes deployments traceable and enables precise rollbacks without relying on the mutable `latest` tag.

---

## Assumptions

- The AWS account has sufficient service limits for EKS, EC2, and ELB resources
- The EC2 key pair `solomon-key` is created in the same region before running Terraform
- The GitHub repository is accessible from the Jenkins EC2 (public repo or SSH key configured)
- The deployer has `AdministratorAccess` or equivalent IAM permissions to run Terraform
- Region is `us-east-1` — change `aws_region` in `variables.tf` if needed

---

## Limitations & Improvements

| Limitation                              | Improvement                                                        |
|-----------------------------------------|--------------------------------------------------------------------|
| Public subnets for worker nodes         | Move nodes to private subnets with NAT Gateway                     |
| No HTTPS                                | Add ACM certificate + HTTPS listener on the LoadBalancer           |
| No Terraform remote state               | Enable S3 backend with DynamoDB state locking                      |
| No GitHub webhook trigger               | Configure Jenkins webhook for automatic pipeline trigger on push   |
| Single region deployment                | Add multi-region or multi-AZ failover                              |
| No Horizontal Pod Autoscaler            | Add HPA based on CPU/memory metrics                                |
| CloudWatch basic logging only           | Enable Container Insights for full pod-level metrics               |
| No secrets management                   | Use AWS Secrets Manager or Kubernetes Secrets for sensitive config |

---

## Teardown

To avoid ongoing AWS charges after the assessment:

```bash
# Delete Kubernetes resources first
kubectl delete namespace solomon-ns

# Destroy all Terraform-managed infrastructure
cd terraform
terraform destroy
```
