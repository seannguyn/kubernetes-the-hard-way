###############################################################################
# Provider Configuration
###############################################################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.82.2"
    }
  }
  required_version = ">= 1.10"
}

provider "aws" {
  region = "ap-southeast-2"
}

###############################################################################
# Data: Debian 12 AMI (ARM64)
# Note: The owner and filter below may need to be updated to match
#       an official Debian 12 ARM64 AMI in your region.
# Link: https://ap-southeast-2.console.aws.amazon.com/ec2/home?region=ap-southeast-2#Images:visibility=public-images;owner=136693071363;imageName=:debian-12-arm64;v=3;$case=tags:false%5C,client:false;$regex=tags:false%5C,client:false
###############################################################################
data "aws_ami" "debian12_arm64" {
  most_recent = true
  owners      = ["136693071363"] # Official Debian AMIs owner ID; adjust if needed
  filter {
    name   = "name"
    values = ["debian-12-arm64-*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

###############################################################################
# Networking: Create a VPC, Subnet, and Internet Gateway
###############################################################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "k8s-igw"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block             = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-2a"

  tags = {
    Name = "k8s-public-subnet"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "k8s-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

###############################################################################
# Security Group
###############################################################################

variable "my_ip" {
  type        = string
  description = "Your public IP for SSH access"
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allows SSM and inbound SSH for EC2 Instance Connect"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow SSH from EC2 Instance Connect (IPv6)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks      = ["${var.my_ip}/32"]
  }

  egress {
    description     = "Allow all outbound traffic"
    protocol        = "-1" # -1 means all protocols
    from_port       = 0
    to_port         = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  revoke_rules_on_delete = true

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "example" {
  security_group_id = aws_security_group.ec2_sg.id

  description                   = "Allow all inbound traffic from instances in this same SG"
  ip_protocol                   = "-1" # -1 means "all protocols"
  from_port                     = 0
  to_port                       = 0
  referenced_security_group_id  = aws_security_group.ec2_sg.id
}

###############################################################################
# Common EC2 arguments
###############################################################################
resource "tls_private_key" "mykey" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 2) Create an AWS key pair with the public key
resource "aws_key_pair" "mykey" {
  key_name   = "mykey"
  public_key = tls_private_key.mykey.public_key_openssh
}

locals {
  common_ec2_args = {
    instance_type_jumpbox        = "t4g.micro"
    volume_size_jumpbox          = 10
    instance_type_k8s_host       = "t4g.small"
    volume_size_k8s_host         = 20
    ami                          = data.aws_ami.debian12_arm64.id
    subnet_id                    = aws_subnet.public_subnet.id
    vpc_security_group_ids       = [aws_security_group.ec2_sg.id]
    associate_public_ip_address  = true
    instance_initiated_shutdown_behavior = "terminate"

    # You can define ebs_block_device here or inline in each resource.
    ebs_block_device = []
    tags            = {}
  }
}

###############################################################################
# EC2 Instances (Spot) - Jumpbox
###############################################################################
resource "aws_instance" "jumpbox" {
  ami                         = local.common_ec2_args.ami
  subnet_id                   = local.common_ec2_args.subnet_id
  vpc_security_group_ids      = local.common_ec2_args.vpc_security_group_ids
  associate_public_ip_address = local.common_ec2_args.associate_public_ip_address
  key_name                    = aws_key_pair.mykey.key_name
  instance_type               = local.common_ec2_args.instance_type_jumpbox
  instance_market_options     {
    market_type = "spot"
    spot_options {
      # https://aws.amazon.com/ec2/pricing/on-demand/
      max_price = "0.0106"
    }
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # 1) Add the public key to /root/.ssh/authorized_keys
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    echo "${tls_private_key.mykey.public_key_openssh}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # 2) Permit root login in sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

    # 3) Restart SSH to apply changes
    systemctl restart ssh

    # 4) Copy private and public ssh key
    echo "${tls_private_key.mykey.private_key_pem}" > /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa

    echo "${tls_private_key.mykey.public_key_openssh}" > /root/.ssh/id_rsa.pub
    chmod 644 /root/.ssh/id_rsa.pub
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = local.common_ec2_args.volume_size_jumpbox
  }

  tags = {
    Name = "jumpbox"
  }
}

###############################################################################
# EC2 Instances (Spot) - K8s Nodes
###############################################################################
resource "aws_instance" "k8s" {
  for_each = {
    server = { name_tag = "server" }
    node0  = { name_tag = "node-0" }
    node1  = { name_tag = "node-1" }
  }

  ami                         = local.common_ec2_args.ami
  subnet_id                   = local.common_ec2_args.subnet_id
  vpc_security_group_ids      = local.common_ec2_args.vpc_security_group_ids
  associate_public_ip_address = local.common_ec2_args.associate_public_ip_address
  key_name                    = aws_key_pair.mykey.key_name
  instance_type               = local.common_ec2_args.instance_type_k8s_host
  instance_market_options     {
    market_type = "spot"
    spot_options {
      # https://aws.amazon.com/ec2/pricing/on-demand/
      max_price = "0.0212"
    }
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # 1) Add the public key to /root/.ssh/authorized_keys
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    echo "${tls_private_key.mykey.public_key_openssh}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # 2) Permit root login in sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

    # 3) Restart SSH to apply changes
    systemctl restart ssh
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = local.common_ec2_args.volume_size_k8s_host
  }

  tags = {
    Name = each.value.name_tag
  }
}

###############################################################################
# Outputs
###############################################################################
output "vpc_id" {
  description = "The ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "The ID of the created public subnet"
  value       = aws_subnet.public_subnet.id
}

output "jumpbox_public_ip" {
  description = "Public IP of the jumpbox"
  value       = aws_instance.jumpbox.public_ip
}

output "jumpbox_private_ip" {
  description = "Private IP of the jumpbox"
  value       = aws_instance.jumpbox.private_ip
}

output "server_public_ip" {
  description = "Public IP of the server"
  value       = aws_instance.k8s["server"].public_ip
}

output "server_private_ip" {
  description = "Private IP of the server"
  value       = aws_instance.k8s["server"].private_ip
}

output "node0_public_ip" {
  description = "Public IP of node-0"
  value       = aws_instance.k8s["node0"].public_ip
}

output "node0_private_ip" {
  description = "Private IP of node-0"
  value       = aws_instance.k8s["node0"].private_ip
}

output "node1_public_ip" {
  description = "Public IP of node-1"
  value       = aws_instance.k8s["node1"].public_ip
}

output "node1_private_ip" {
  description = "Private IP of node-1"
  value       = aws_instance.k8s["node1"].private_ip
}

output "my_public_key" {
  description = "The public key used for SSH"
  value       = tls_private_key.mykey.public_key_openssh
}

output "my_private_key" {
  description = "The private key used for SSH"
  value       = tls_private_key.mykey.private_key_pem
  sensitive   = true
}
