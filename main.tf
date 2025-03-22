provider "aws" {
  region = "ap-northeast-1"
}

# Create a VPC
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
}

# Create a public subnet
resource "aws_subnet" "public" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    map_public_ip_on_launch = true
}
# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create a route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
# Associate the route table with the public subnet
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a security group
resource "aws_security_group" "jenkins_sg" {
    name = "jenkins_sg"
    vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "jenkins_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_ec2.id
  allocation_id = aws_eip.jenkins_eip.id
}

# Create an EC2 instance
resource "aws_instance" "jenkins_ec2" {
    ami = "ami-0599b6e53ca798bb2"
    instance_type = "t3.small"
    subnet_id = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
    associate_public_ip_address = true
    iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name
    key_name = "jenkins_test"
     user_data = <<-EOF
              #!/bin/bash
              sudo dnf update -y
              sudo dnf install git java-17-amazon-corretto -y
              sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              sudo dnf install jenkins -y
              # 建立新的 tmp 目錄
              sudo mkdir -p /var/jenkins_home/tmp
              sudo chown -R jenkins:jenkins /var/jenkins_home/tmp

              # 修改 Jenkins 啟動參數，指定新的 tmp 目錄
              echo 'JENKINS_JAVA_OPTIONS="-Djava.io.tmpdir=/var/jenkins_home/tmp"' | sudo tee -a /etc/sysconfig/jenkins

              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              EOF
    tags = {
        Name = "jenkins_ec2"
    }
}

# IAM Role：允許 EC2 擁有此角色
resource "aws_iam_role" "jenkins_ec2_role" {
  name = "jenkins_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Instance Profile：綁定 IAM Role 給 EC2 使用
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_instance_profile"
  role = aws_iam_role.jenkins_ec2_role.name
}

# IAM Policy Attachments：給予 ECS / ECR 權限
resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_ecs_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}