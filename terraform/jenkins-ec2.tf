# Fetch the latest Amazon Linux 2023 AMI (free tier eligible)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security Group for Jenkins EC2
resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Allow SSH and Jenkins web UI access"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Jenkins web UI
  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-jenkins-sg"
  }
}

# IAM Role for Jenkins EC2 (allows ECR push and EKS access)
resource "aws_iam_role" "jenkins_role" {
  name = "${var.project_name}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_policy" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_eks_policy" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Allow Jenkins to describe and update EKS
resource "aws_iam_role_policy" "jenkins_eks_inline" {
  name = "jenkins-eks-access"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}

# User data script: installs all required tools on first boot
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.jenkins_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name
  key_name               = var.jenkins_key_name

  # 20GB root volume — Jenkins + Java 21 + Docker require more than the default 8GB
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/user-data.log 2>&1

    echo "=== Starting user data script ==="

    # Update system
    dnf update -y

    # Install essential tools (curl replaces wget on AL2023, unzip needed for AWS CLI)
    dnf install -y curl unzip git

    # ── Java 21 (Jenkins 2.463+ requires Java 21 minimum) ──
    dnf install -y java-21-amazon-corretto
    java -version

    # ── Jenkins ──
    # Use curl (not wget) and --nogpgcheck to avoid GPG key mismatch issues on AL2023
    curl -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins --nogpgcheck
    systemctl enable jenkins
    systemctl start jenkins
    echo "Jenkins installed and started"

    # ── Docker ──
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    # Add jenkins and ec2-user to docker group so they can run docker commands
    usermod -aG docker jenkins
    usermod -aG docker ec2-user
    echo "Docker installed and started"

    # ── kubectl ──
    KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl
    kubectl version --client
    echo "kubectl installed"

    # ── AWS CLI v2 (already present on AL2023 but ensure latest) ──
    aws --version
    echo "AWS CLI ready"

    # Restart Jenkins to pick up docker group membership
    systemctl restart jenkins
    echo "=== User data script complete ==="
  EOF

  tags = {
    Name = "${var.project_name}-jenkins"
  }
}
