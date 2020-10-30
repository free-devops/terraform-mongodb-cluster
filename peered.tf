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
data "aws_caller_identity" "second" {
  provider = aws.peered
  count = local.second_count == 0 ? 0 : 1
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
# SSH Key
########################################################################
module "key_pair_second" {
  source = "terraform-aws-modules/key-pair/aws"
  version = "0.5.0"

  providers = {
    aws = aws.peered
  }

  create_key_pair = local.second_count == 0 ? false : true

  key_name   = local.name
  public_key = tls_private_key.this.public_key_openssh
}

########################################################################
# Security Groups
########################################################################
module "sg_second" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "3.16.0"

  providers = {
    aws = aws.peered
  }

  create =  local.second_count == 0 ? false : true

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
module "ec2_cluster_second" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"


  providers = {
    aws = aws.peered
  }

  instance_count = local.second_count
  name                   = local.name
  num_suffix_format = "-%d.${var.aws_peered_region}.${var.domain}"

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
  }

  volume_tags = {
    Terraform = "true"
    Environment = var.environment
  }

}

########################################################################
# EBS Volumes through resource
########################################################################
resource "aws_volume_attachment" "second" {
  provider = aws.peered
  force_detach = true

  count = local.second_count

  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.second[count.index].id
  instance_id = module.ec2_cluster_second.id[count.index]
}

resource "aws_ebs_volume" "second" {
  provider = aws.peered

  count = local.second_count

  availability_zone = element(local.second_azs, count.index)
  size              = var.volume_size
  encrypted         = var.volume_encrypt
  type              = var.volume_type
  iops              = var.volume_type == "io1" || var.volume_type == "io2" ? var.volume_iops : null


  tags = {
    Terraform   = "true"
    Environment = var.environment
    Name        = local.second_count > 1 ? format("%s${var.num_suffix_format}.%s.%s", local.name, count.index + 1, var.aws_peered_region, var.domain) : local.name
  }
}

# register DNS for the EC2 in private zone
# TODO Implement Through Module (similar to ec2 for naming)
resource "aws_route53_record" "second" {
  provider = aws.peered

  count   = local.second_count
  name    = local.second_count > 1 ? format("%s${var.num_suffix_format}.%s.%s", local.name, count.index + 1, var.aws_peered_region, var.domain) : local.name
  type    = "A"
  zone_id = var.zone_id
  records = [module.ec2_cluster_second.private_ip[count.index]]
  ttl     = "60"
}