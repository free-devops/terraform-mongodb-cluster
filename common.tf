########################################################################
# Locals
########################################################################
locals {
  name = "${var.name}-${var.environment}"
  # snoo-mongo-cr-stage
  second_count = lookup(var.instances_count, "second", 0)
  second_azs = lookup(var.azs, "second", [])
  policy_arns = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ])
}

########################################################################
# User-data
########################################################################
data "template_file" "init" {
  template = file("${path.module}/files/user-data.tpl")
  vars = {
    mongo_key = base64encode(random_password.mongo_key.result)
    instance_name = "${local.name}-1.${var.aws_region}.${var.domain}"
    instance_count = var.instances_count["first"]+local.second_count
    region = var.aws_region
    peered_region = var.aws_peered_region != "" ? var.aws_peered_region : ""
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