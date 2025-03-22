output "vpc_id" {
  value = aws_vpc.main.cidr_block
}

output "subnet_id_public_cidr_block" {
  value = aws_subnet.public.cidr_block
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