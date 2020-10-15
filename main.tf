########################################################################
# Locals
########################################################################
locals {
  name = "${var.name}-${var.environment}"
  second_count = lookup(var.instances_count, "second", 0)
  policy_arns = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])
}
########################################################################
# Peered Provider Block
########################################################################
provider "aws" {
  alias   = "peered"
  profile = var.aws_profile
  region  = var.aws_peered_region
}
########################################################################
# Data
########################################################################
data "aws_caller_identity" "first" {
}

data "aws_caller_identity" "second" {
  count = local.second_count == 0 ? 0 : 1
  provider = aws.peered
}

data "aws_ami" "ubuntu-20_04_first" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name = "name"
    values = [
    "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

data "aws_ami" "ubuntu-20_04_second" {
  provider = aws.peered

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name = "name"
    values = [
    "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
########################################################################
# User-data
########################################################################
data "template_file" "init" {
  template = "${file("${path.module}/files/user-data.tpl")}"
  vars = {
    mongo_key = base64encode(random_password.mongo_key.result)
    instance_name = "${local.name}-1"
    instance_count = var.instances_count["first"]+local.second_count
    region = var.aws_region
    peered_region = var.aws_peered_region
    name = "${local.name}*"
    mongo_pass = random_password.mongo_pass.result
    mongo_version = var.mongo_version
  }
}
########################################################################
# Mongo Password Generators
########################################################################
resource "random_password" "mongo_key" {
  length = 750
  special = true
  override_special = "_%@"
}

resource "random_password" "mongo_pass" {
  length = 16
  special = true
  override_special = "_%@"
}
########################################################################
# SSH Key
########################################################################
resource "tls_private_key" "this" {
  algorithm = "RSA"
}

module "key_pair_first" {
  source = "terraform-aws-modules/key-pair/aws"
  version = "0.5.0"

  key_name   = local.name
  public_key = tls_private_key.this.public_key_openssh
}

module "key_pair_second" {
  source = "terraform-aws-modules/key-pair/aws"
  version = "0.5.0"

  create_key_pair = local.second_count == 0 ? false : true
  providers = {
    aws = aws.peered
  }

  key_name   = local.name
  public_key = tls_private_key.this.public_key_openssh
}
########################################################################
# Security Groups
########################################################################
module "sg_first" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.16.0"

  name                = local.name
  description         = "Security group for mongodb cross-region access"
  ingress_cidr_blocks = var.cidr_blocks

  vpc_id = var.vpc_ids["first"]

  ingress_rules = ["ssh-tcp", "mongodb-27017-tcp"]
  egress_rules  = ["all-all"]
}

module "sg_second" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.16.0"

  create =  local.second_count == 0 ? false : true
  providers = {
    aws = aws.peered
  }

  name                = local.name
  description         = "Security group for mongodb cross-region access"
  ingress_cidr_blocks = var.cidr_blocks

  vpc_id = lookup(var.vpc_ids, "second", "")

  ingress_rules = ["ssh-tcp", "mongodb-27017-tcp"]
  egress_rules  = ["all-all"]
}
########################################################################
# EC2 Instances
########################################################################
module "ec2_cluster_first" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  name           = local.name
  instance_count = var.instances_count["first"]

  ami                    = data.aws_ami.ubuntu-20_04_first.id
  instance_type          = var.instance_type
  key_name               = module.key_pair_first.this_key_pair_key_name
  vpc_security_group_ids = [module.sg_first.this_security_group_id]
  subnet_ids             = var.subnet_ids["first"]
  user_data              = data.template_file.init.rendered
  iam_instance_profile	 = aws_iam_instance_profile.this.name

  root_block_device     = [
    {
      volume_size = var.root_volume_size
      encrypted   = var.root_volume_encrypt
    }
  ]

  tags = {
    Mongo = "ready"
    Terraform = "true"
    Environment = var.environment
  }

  volume_tags = {
    Terraform = "true"
    Environment = var.environment
  }
}

module "ec2_cluster_second" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  providers = {
    aws = aws.peered
  }

  name           = local.name
  instance_count = local.second_count

  ami                    = data.aws_ami.ubuntu-20_04_second.id
  instance_type          = var.instance_type
  key_name               = module.key_pair_second.this_key_pair_key_name
  vpc_security_group_ids = [module.sg_second.this_security_group_id]
  subnet_ids             = lookup(var.subnet_ids, "second", [])
  user_data              = data.template_file.init.rendered
  iam_instance_profile	 = aws_iam_instance_profile.this.name

  root_block_device     = [
    {
      volume_size = var.root_volume_size
      encrypted   = var.root_volume_encrypt
    }
  ]

  tags = {
    Mongo = "ready"
    Terraform = "true"
    Environment = var.environment
    Name = "${var.name}-${var.environment}"
  }

  volume_tags = {
    Terraform = "true"
    Environment = var.environment
  }

}
########################################################################
# EBS Volumes through Module
########################################################################
module "ebs_volume_first" {
  source  = "free-devops/volume/ebs"
  version = "~> 1.1"

  name = local.name
  instance_count = var.instances_count["first"]

  instance_ids = module.ec2_cluster_first.id
  availability_zones = module.ec2_cluster_first.availability_zone
  force_detach = true
  encrypted = var.volume_encrypt
  volume_size = var.volume_size
  volume_type = var.volume_type
  volume_iops = var.volume_iops

  tags = {
    Terraform = "true"
    Environment = var.environment
  }
}

module "ebs_volume_second" {
  source  = "free-devops/volume/ebs"
  version = "~> 1.1"

  providers = {
    aws = aws.peered
  }

  name = local.name
  instance_count = local.second_count

  instance_ids = module.ec2_cluster_second.id
  availability_zones = module.ec2_cluster_second.availability_zone
  force_detach = true
  encrypted = var.volume_encrypt
  volume_size = var.volume_size
  volume_type = var.volume_type
  volume_iops = var.volume_iops

  tags = {
    Terraform = "true"
    Environment = var.environment
  }
}
########################################################################
# EBS Volumes through resource
########################################################################
//resource "aws_volume_attachment" "first" {
//  count = 3
//
//
//  device_name = "/dev/xvdh"
//  volume_id   = aws_ebs_volume.first[count.index].id
//  instance_id = module.ec2_cluster_first.id[count.index]
//}
//
//resource "aws_ebs_volume" "first" {
//  count = 3
//
//  availability_zone = module.ec2_cluster_first.availability_zone[count.index]
//  size              = 30
//  encrypted         = true
//}
//
//
//resource "aws_volume_attachment" "second" {
//  count = 2
//
//  provider = aws.peered
//
//  device_name = "/dev/xvdh"
//  volume_id   = aws_ebs_volume.second[count.index].id
//  instance_id = module.ec2_cluster_second.id[count.index]
//}
//
//resource "aws_ebs_volume" "second" {
//  count = 2
//
//  provider = aws.peered
//
//  availability_zone = module.ec2_cluster_eu.availability_zone[count.index]
//  size              = 30
//  encrypted         = true
//}
########################################################################
# IAM Role
########################################################################
resource "aws_iam_role" "this" {
  name = local.name
  description = "Allows EC2 instances to call AWS services on your behalf."
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = local.policy_arns
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name
}