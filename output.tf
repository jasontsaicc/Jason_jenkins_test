output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_cidrs" {
  value = module.vpc.public_subnets_cidr_blocks
}

output "jenkins_ec2_availability_zone" {
  value = aws_instance.jenkins_ec2.availability_zone
}

output "jenkins_ec2_private_ip" {
  value = aws_instance.jenkins_ec2.private_ip
}

output "jenkins_ec2_public_ip" {
  value = aws_instance.jenkins_ec2.public_ip
}

output "jenkins_eip" {
  value = aws_eip.jenkins_eip.public_ip
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app_repo.repository_url
}

output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.app_cluster.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app_service.name
}