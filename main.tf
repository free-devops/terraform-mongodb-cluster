
########################################################################
# Data
########################################################################
data "aws_caller_identity" "first" {
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

########################################################################
# SSH Key
########################################################################
module "key_pair_first" {
  source = "terraform-aws-modules/key-pair/aws"
  version = "0.5.0"

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

########################################################################
# EC2 Instances
########################################################################
module "ec2_cluster_first" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  instance_count         = var.instances_count["first"]
  name                   = local.name
  num_suffix_format = "-%d.${var.aws_region}.${var.domain}"

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

  volume_tags ={
    Terraform = "true"
    Environment = var.environment
    }
}


########################################################################
# EBS Volumes through Module
########################################################################
//module "ebs_volume_first" {
//  source  = "free-devops/volume/ebs"
//  version = "~> 1.1"
//
//  name = local.name
//  instance_count = var.instances_count["first"]
//
//  instance_ids = module.ec2_cluster_first.id
//  availability_zones = module.ec2_cluster_first.availability_zone
//  force_detach = true
//  encrypted = var.volume_encrypt
//  volume_size = var.volume_size
//  volume_type = var.volume_type
//  volume_iops = var.volume_iops
//
//  tags = {
//    Terraform = "true"
//    Environment = var.environment
//  }
//}
//
//module "ebs_volume_second" {
//  source  = "free-devops/volume/ebs"
//  version = "~> 1.1"
//
//  providers = {
//    aws = aws.peered
//  }
//
//  name = local.name
//  instance_count = local.second_count
//
//  instance_ids = module.ec2_cluster_second.id
//  availability_zones = module.ec2_cluster_second.availability_zone
//  force_detach = true
//  encrypted   = var.volume_encrypt
//  volume_size = var.volume_size
//  volume_type = var.volume_type
//  volume_iops = var.volume_iops
//
//  tags = {
//    Terraform = "true"
//    Environment = var.environment
//  }
//}
########################################################################
# EBS Volumes through resource
########################################################################
resource "aws_volume_attachment" "first" {
  force_detach = true

  count = var.instances_count["first"]


  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.first[count.index].id
  instance_id = module.ec2_cluster_first.id[count.index]
}

resource "aws_ebs_volume" "first" {
  count = var.instances_count["first"]

  availability_zone = element(var.azs["first"], count.index)
  size              = var.volume_size
  encrypted         = var.volume_encrypt
  type              = var.volume_type
  iops              = var.volume_type == "io1" || var.volume_type == "io2" ? var.volume_iops : null


  tags = {
    Terraform = "true"
    Environment = var.environment
    Name        = var.instances_count["first"] > 1 ? format("%s${var.num_suffix_format}.%s.%s", local.name, count.index + 1, var.aws_region, var.domain) : local.name
  }
}


# register DNS for the EC2 in private zone
# TODO Implement Through Module (similar to ec2 for naming)
resource "aws_route53_record" "first" {
  count   = var.instances_count["first"]
  name    = var.instances_count["first"] > 1 ? format("%s${var.num_suffix_format}.%s.%s", local.name, count.index + 1, var.aws_region, var.domain) : local.name
  type    = "A"
  zone_id = var.zone_id
  records = [module.ec2_cluster_first.private_ip[count.index]]
  ttl     = "60"
}