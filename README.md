
# Node.JS - MySQL Web App. <br><br> Deployment automation with Terraform

<br>

> **Note:** The series of demo projects experimenting with the same Node.js app.<br><br>
> In this demo I automate the deployment of the app using Terraform.


## Summary
This is a simple Node.JS Express application. It has a two-layer architecture: application layer and data layer. It connects to a MySQL database hosted on an AWS RDS instance, allowing for CRUD operations. Express provides a robust set of features for web and mobile applications.

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/938f8409-1cf9-4ae5-a5fd-549a395948da" width="700px"/>
</p>

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/08a5a711-8f1d-47ec-93fb-f73c430b47b9" width="700px"/>
</p>

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/afb8cc08-2f0c-4dfe-84ae-0bf886ae0053" width="700px"/>
</p>


## Prerequisites
- AWS Account
- Proper Permissions for your AWS user
- Configure AWS with the command ```aws configure```
- Terraform installed (https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- MySQL installed (https://muleif.medium.com/how-to-install-mysql-on-amazon-linux-2023-5d39afa5bf11)
- An EC2 instance for a manual deployment case (I am using Amazon Linux 2)
- An RDS instance for a manual deployment case  (I am using "db.t2.micro" "mysql")

## Running the App on AWS EC2 and RDS MySQL Instances

### 1. Automated Deployment with Terraform

#### Template Description
The Terraform configuration deploys resources on AWS. It sets up a VPC, subnets, security groups, EC2, and RDS instances. After the EC2 instance launches, it runs a script to install node.js and imports 

The RDS instance is created with specified configurations and a script is run to set up the database.

> **Terraform files:** [GitHub Link](https://github.com/otammato/CRUD_WebApp_NodeJS_AWS_RDS_MySql/tree/main/Terraform_template)

<details markdown=1><summary markdown="span">Terraform main.tf here</summary>

```tf
provider "aws" {
  region                    = "us-east-1"
  shared_config_files       = ["/home/ec2-user/.aws/config"]
  shared_credentials_files  = ["/home/ec2-user/.aws/credentials"]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "current-ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_default_vpc" "default" {
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "Default VPC"
  }
}

data "aws_vpc" "default" {
  default = true
}

locals {
  subnet_count = 2  # Adjust this to the desired number of subnets
  base_cidr_block = data.aws_vpc.default.cidr_block
  subnet_bits = 8  # You can adjust the number of bits as needed
}

resource "aws_subnet" "subnets" {
  count = local.subnet_count

  vpc_id            = aws_default_vpc.default.id
  cidr_block        = cidrsubnet(local.base_cidr_block, local.subnet_bits, count.index + 130)  # Offset by some number to avoid conflicts
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "test-subnet-${count.index + 1}"
  }
}


resource "aws_security_group" "ec2_security_group" {
  name        = "test-ec2-security-group1"
  description = "Allow ssh access"
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

resource "aws_instance" "ec2_instance" {
  ami           = data.aws_ssm_parameter.current-ami.value
  instance_type = "t2.medium"
  subnet_id     = aws_subnet.subnets[0].id  # Use the first subnet created
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  associate_public_ip_address = true
  key_name      = "test_delete"

  user_data     = <<-EOF
#!/bin/bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 16.0.0
nvm use 16.0.0
  EOF
  
  tags = {
    Name = "web-server-terr"
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "test-rds-security-group1"
  description = "Allow mysql access"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Add your RDS ingress rules here
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "test-rds-subnet-group1"
  subnet_ids = aws_subnet.subnets[*].id
}

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
  publicly_accessible     = true
}


resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.rds_instance] # Wait for the DB to be ready
  provisioner "local-exec" {
    command = "mysql -h ${aws_db_instance.rds_instance.address} -u ${aws_db_instance.rds_instance.username} --password=${var.dbpassword}  ${var.dbname} < my_sql.sql"
  }
}


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
```
</details>

#### Deploying the Template
```bash
terraform init
terraform validate
terraform plan
terraform apply
```

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/54446e4a-f407-4de6-ab18-2adc534a2a13" width="700px"/>
</p>

### 2. Manual Launch
#### Clone the Repository
```bash
git clone https://github.com/otam-mato/nodejs_mysql_web_app_terraform.git
cd CRUD_WebApp_NodeJS_AWS_RDS_MySql/resources/codebase_partner/
```

#### Setup
```bash
# Install Node, NPM, and dependencies
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 16.0.0
nvm use 16.0.0
npm install

# Set Environment Variables
export APP_DB_HOST=<paste here the output endpoint of the created RDS instance> \
export APP_DB_USER=admin \
export APP_DB_PASSWORD="<your password>" \
export APP_DB_NAME=COFFEE \
```

```bash
# Testing connection to the database
mysql -h database-2.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com -P 3306 -u admin -p
```

```sql
create DATABASE coffee;
use coffee;
create table suppliers(
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  address VARCHAR(255) NOT NULL,
  city VARCHAR(255) NOT NULL,
  state VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  phone VARCHAR(100) NOT NULL,
  PRIMARY KEY ( id )
);
```

### 3. Testing the App

```zsh
cd CRUD_WebApp_NodeJS_AWS_RDS_MySql/resources/codebase_partner/
npm install
npm start
```
If you do not set the env vars when starting the app the values 
from `app/config/config.js` will be used

Access the app via the DNS or public IP of the EC2 instance. Confirm the RDS connection using the MySQL command.

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/08a5a711-8f1d-47ec-93fb-f73c430b47b9" width="700px"/>
</p>

<p align="center">
  <img src="https://github.com/otam-mato/nodejs_mysql_web_app_terraform/assets/113034133/afb8cc08-2f0c-4dfe-84ae-0bf886ae0053" width="700px"/>
</p>
