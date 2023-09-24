# Provider Configuration
provider "aws" {
  region                    = "us-east-1"
  shared_config_files       = ["/home/ec2-user/.aws/config"] # never hard-code the sensitive data
  shared_credentials_files  = ["/home/ec2-user/.aws/credentials"] # never hard-code the sensitive data
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "current-ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

data "aws_vpc" "default" {
  default = true
}

# Local Variables
locals {
  subnet_count    = 2  # Adjust this to the desired number of subnets
  base_cidr_block = data.aws_vpc.default.cidr_block
  subnet_bits     = 8  # You can adjust the number of bits as needed
}

# I am using a Default VPC for simplicity
resource "aws_default_vpc" "default" {
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "Default VPC"
  }
}

# Subnets
resource "aws_subnet" "subnets" {
  count = local.subnet_count

  vpc_id            = aws_default_vpc.default.id
  cidr_block        = cidrsubnet(local.base_cidr_block, local.subnet_bits, count.index + 130)  # Offset by some number to avoid conflicts
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "test-subnet-${count.index + 1}"
  }
}

# EC2 Security Group
resource "aws_security_group" "ec2_security_group" {
  name        = "test-ec2-security-group1"
  description = "Allow ssh, http, and custom application port access"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Add your SSH ingress rules here
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Add your HTTP ingress rules here
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Add your custom application port ingress rules here
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "ec2_instance" {
  ami           = data.aws_ssm_parameter.current-ami.value
  instance_type = "t2.medium"
  subnet_id     = aws_subnet.subnets[0].id  # Use the first subnet created
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  associate_public_ip_address = true
  key_name      = "test_delete"

  user_data     = <<-EOF
#!/bin/bash
sudo su
sudo yum install -y git
git clone https://github.com/otam-mato/nodejs_mysql_web_app_terraform.git /home/ec2-user/nodejs_mysql_web_app_terraform
cd /home/ec2-user/nodejs_mysql_web_app_terraform/resources/codebase_partner
  EOF
  
  tags = {
    Name = "web-server-terr"
  }
}

# RDS Security Group
resource "aws_security_group" "rds_security_group" {
  name        = "test-rds-security-group1"
  description = "Allow MySQL access"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Put your ip addres here for security
    # security_groups  = [aws_security_group.ec2_security_group.id] # For production restrict the RDS intance to be accesible only from created EC2 instance.
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "test-rds-subnet-group1"
  subnet_ids = aws_subnet.subnets[*].id
}

# RDS Instance
resource "aws_db_instance" "rds_instance" {
  engine                  = "mysql"
  engine_version          = "5.7"
  instance_class          = "db.t2.micro"
  db_name                 = var.dbname
  username                = var.dbuser
  password                = var.dbpassword
  allocated_storage       = 20
  vpc_security_group_ids  = [aws_security_group.rds_security_group.id]
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
  skip_final_snapshot     = true
  publicly_accessible     = true # Temporary set to true to unrestrict public internet access for testing the connectivity. Must be closed in production
}

# This part can be used to automate the import of the existing database into the RDS. Can be commented out if you plan to set up the database manually.
resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.rds_instance] # Wait for the DB to be ready
  provisioner "local-exec" {
    command = "mysql -h ${aws_db_instance.rds_instance.address} -u ${aws_db_instance.rds_instance.username} --password=${var.dbpassword}  ${var.dbname} < my_sql.sql"
  }
}

# Outputs
output "rds_hostname" {
  description = "RDS instance hostname"
  value       = aws_db_instance.rds_instance.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.rds_instance.port
}

output "rds_username" {
  description = "RDS instance root username"
  value       = aws_db_instance.rds_instance.username
  sensitive   = true
}

output "rds_endpoint" {
  value = aws_db_instance.rds_instance.endpoint
}

output "ec2_public_dns" {
  value = aws_instance.ec2_instance.public_dns
}

output "ec2_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}


