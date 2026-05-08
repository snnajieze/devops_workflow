variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used to tag and name resources"
  type        = string
  default     = "solomon-app"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

# VPC
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# EKS
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "DEMO_CLUSTER"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_min_nodes" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "eks_max_nodes" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 3
}

# Jenkins EC2
variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "jenkins_key_name" {
  description = "Name of the existing EC2 key pair for SSH access to Jenkins"
  type        = string
  default     = "solomon-key"
}

variable "your_ip_cidr" {
  description = "Your local IP in CIDR notation for SSH access to Jenkins (e.g. 102.89.x.x/32)"
  type        = string
  default     = "0.0.0.0/0" # Restrict this to your actual IP in production
}
