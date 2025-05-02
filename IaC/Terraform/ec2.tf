terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Add variables for key pair
variable "key_pair_name" {
  type        = string
  description = "Name of the key pair to create in AWS"
}

variable "public_key_path" {
  type        = string
  description = "Path to the public key file"
}

# Add variables for EC2 instance
variable "instance_type" {
  type        = string
  description = "Type of EC2 instance to launch"
  default     = "t2.nano"
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use for the EC2 instance"
  default     = "ami-075686beab831bb7f"
}

provider "aws" {
  region = "us-east-1" # Change this to your desired region
}

# Create key pair from provided public key
resource "aws_key_pair" "deployer" {
  key_name   = var.key_pair_name
  public_key = file(var.public_key_path)
}

# Get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_string" "random_name" {
  length  = 6
  special = false
  upper   = false
}

data "aws_ec2_instance" "app_server" {
  filter {
    name   = "tag:Name"
    values = ["FileUploadApp"]
  }
}

locals {
  total_machines = length([for instance in aws_instance.app_server : instance.id if lookup(instance.tags, "Name", "") == "FileUploadApp"])
}
# Create EC2 instance
resource "aws_instance" "app_server" {
  count         = local.total_machines > 7 ? 0 : 1
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.default.ids[0]
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = file("${path.module}/scripts/user_data.sh")

  tags = {
    Name = "FileUploadApp"
  }
}

# Create security group
resource "aws_security_group" "app_sg" {
  name        = "file-upload-app-sg-${random_string.random_name.result}"
  description = "Security group for File Upload App"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "FileUploadAppSG"
  }
}

# Output the public IP
output "public_ip" {
  value = aws_instance.app_server.public_ip
}