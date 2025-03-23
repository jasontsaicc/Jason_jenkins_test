# 使用 AWS 官方 VPC Module 建立多 AZ 公網 VPC 架構
provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = "jenkins-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

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

resource "aws_eip" "jenkins_eip" {
  domain = "vpc"
}

resource "aws_instance" "jenkins_ec2" {
  ami                         = "ami-0599b6e53ca798bb2"
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  key_name                    = "jenkins_test"

  user_data = <<-EOF
              #!/bin/bash
              sudo fallocate -l 2G /swapfile
              sudo chmod 600 /swapfile
              sudo mkswap /swapfile
              sudo swapon /swapfile
              sudo bash -c 'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab'
              sudo dnf update -y
              sudo dnf install git java-17-amazon-corretto -y
              sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              sudo dnf install jenkins -y
              sudo mkdir -p /var/jenkins_home/tmp
              sudo chown -R jenkins:jenkins /var/jenkins_home/tmp
              echo 'JENKINS_JAVA_OPTIONS="-Djava.io.tmpdir=/var/jenkins_home/tmp"' | sudo tee -a /etc/sysconfig/jenkins
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              EOF

  tags = {
    Name = "jenkins_ec2"
  }
}

resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_ec2.id
  allocation_id = aws_eip.jenkins_eip.id
}

resource "aws_iam_role" "jenkins_ec2_role" {
  name = "jenkins_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_instance_profile"
  role = aws_iam_role.jenkins_ec2_role.name
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_ecs_access" {
  role       = aws_iam_role.jenkins_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_ecr_repository" "app_repo" {
  name                 = "jenkins-test-app"
  image_tag_mutability = "MUTABLE"
}

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

resource "aws_ecs_cluster" "app_cluster" {
  name = "jenkins-app-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  target_type  = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

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
      protocol      = "tcp"
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
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.jenkins_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http_listener]
}