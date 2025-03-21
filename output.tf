output "vpc_id" {
  value = aws_vpc.main.id
  
}
output "ec2" {
  value = aws_instance.jenkins_ec2.public_ip
}