# AWS VPC Module
provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = "jenkins-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_nat_gateway   = false

  tags = {
    Project     = "jenkins"
    Environment = "dev"
  }
}

# Jenkins EC2 Security Group
resource "aws_security_group" "jenkins_sg" {
  name   = "jenkins_sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins UI"
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

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name   = "alb_sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Jenkins EIP
resource "aws_eip" "jenkins_eip" {
  domain = "vpc"
}

# Jenkins EC2 Instance
resource "aws_instance" "jenkins_ec2" {
  ami                         = "ami-026c39f4021df9abe" # ubuntu 22.04
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  key_name                    = "jenkins_test"
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
                #!/bin/bash -xe

                #### 建立 2GB swap（如果還沒建立）
                if [ ! -f /swapfile ]; then
                  sudo fallocate -l 2G /swapfile
                  sudo chmod 600 /swapfile
                  sudo mkswap /swapfile
                  sudo swapon /swapfile
                  echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
                fi

                #### 更新套件清單與安裝必要工具
                sudo apt-get update -y
                sudo apt-get install -y git openjdk-17-jdk curl gnupg unzip wget

                #### 安裝 AWS CLI v2（僅在未安裝時）
                if ! command -v aws &> /dev/null; then
                  cd /tmp
                  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                  unzip awscliv2.zip
                  sudo ./aws/install
                  rm -rf awscliv2.zip aws
                fi

                #### 匯入 Jenkins GPG Key 與套件來源
                curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
                  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

                echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
                  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
                  /etc/apt/sources.list.d/jenkins.list > /dev/null

                #### 安裝 Jenkins
                sudo apt-get update -y
                sudo apt-get install -y jenkins

                #### 增加 Jenkins 使用的 tmp 空間
                sudo mkdir -p /var/jenkins_home/tmp
                sudo chown -R jenkins:jenkins /var/jenkins_home/tmp
                echo 'JAVA_ARGS="-Djava.io.tmpdir=/var/jenkins_home/tmp"' | sudo tee -a /etc/default/jenkins

                #### 啟動 Jenkins 並等待初始密碼產生
                sudo systemctl enable jenkins
                sudo systemctl start jenkins

                echo "等待 Jenkins 初始密碼產生中..."
                until [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; do
                  sleep 2
                done

                #### 將初始密碼寫入 log，方便從 EC2 console 讀取
                sudo cat /var/lib/jenkins/secrets/initialAdminPassword > /var/log/jenkins-init.log
  EOF
  tags = {
    Name = "jenkins_ec2"
  }
}

# Associate EIP with Jenkins EC2 Instance
resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_ec2.id
  allocation_id = aws_eip.jenkins_eip.id
}

# IAM Role for Jenkins EC2 Instance
resource "aws_iam_role" "jenkins_ec2_role" {
  name = "jenkins_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM Instance Profile for Jenkins EC2 Instance
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_instance_profile"
  role = aws_iam_role.jenkins_ec2_role.name
}

# Attach policies to the Jenkins EC2 Role
resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# Attach ECS  Access policy to the Jenkins EC2 Role
resource "aws_iam_role_policy_attachment" "jenkins_ecs_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# ecr repository
resource "aws_ecr_repository" "app_repo" {
  name                 = "jenkins-test-app"
  image_tag_mutability = "MUTABLE"
}

# ecr repository policy
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Expire untagged images after 7 days",
      selection = {
        tagStatus   = "untagged",
        countType   = "sinceImagePushed",
        countUnit   = "days",
        countNumber = 7
      },
      action = {
        type = "expire"
      }
    }]
  })
}

#ecs cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "jenkins-app-cluster"
}

#ecs task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# 
resource "aws_iam_role_policy_attachment" "ecs_execution_role_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# aws_lb app_alb
resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

# alb target group
resource "aws_lb_target_group" "app_tg" {
  name        = "app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# alb listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family                   = "jenkins-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "app",
    image = "${aws_ecr_repository.app_repo.repository_url}:latest",
    portMappings = [{
      containerPort = 80,
      hostPort      = 80,
      protocol     = "tcp"
    }]
  }])
}


resource "aws_ecs_service" "app_service" {
  name            = "jenkins-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.jenkins_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http_listener]
}