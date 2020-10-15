variable "mongo_version" {
  description = "Mongo Version"
  type = string
  default =  "4.4"
}

variable "instances_count" {
  description = "Number of instances to launch"
  type        = map(number)
}

variable "instance_type" {
  description = "The Instance type to launch"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "The key name to use for the instance"
  type        = string
  default     = "default"
}

variable "name" {
  description = "Instance Name"
  type        = string
  default     = "default"
}

variable "subnet_ids" {
  description = "A map of VPC Subnet IDs to launch in"
  type        = map(list(string))
}

variable "vpc_ids" {
  description = "A map of two vpc ids"
  type        = map(string)
}

variable "cidr_blocks" {
  description = "A list of cidrs to whitelist in security groups"
  type        = list(string)
  default     = []
}

variable "aws_peered_region" {
  description = "Requester AWS Region if cluster is cross-regional"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root Volume Size"
  type        = number
  default     = 10
}

variable "root_volume_encrypt" {
  description = "Root Volume Encryption"
  type        = bool
  default     = true
}

variable "volume_size" {
  description = "EBS Volume Size"
  type        = number
  default     = 30
}

variable "volume_encrypt" {
  description = "EBS Volume Encryption"
  type        = bool
  default     = true
}

variable "volume_type" {
  description = "EBS Volume Type"
  type        = string
  default     = "gp2"
}

variable "volume_iops" {
  description = "EBS Volume IOPS (for io1)"
  type        = number
  default     = 100
}

# Common Variables
variable "aws_profile" {
  description = "The AWS profile to use (e.g. default)"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy to (e.g. us-east-1)"
  type        = string
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}