## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.12.7, < 0.14 |
| aws | >= 2.68, < 4.0 |
| random | ~> 2.0 |
| template | ~> 2.0 |
| tls | ~> 2.2 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 2.68, < 4.0 |
| aws.peered | >= 2.68, < 4.0 |
| random | ~> 2.0 |
| template | ~> 2.0 |
| tls | ~> 2.2 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aws\_profile | The AWS profile to use (e.g. default) | `string` | n/a | yes |
| aws\_region | The AWS region to deploy to (e.g. us-east-1) | `string` | n/a | yes |
| azs | Availability zones | `map(list(string))` | n/a | yes |
| instances\_count | Number of instances to launch | `map(number)` | n/a | yes |
| subnet\_ids | A map of VPC Subnet IDs to launch in | `map(list(string))` | n/a | yes |
| vpc\_ids | A map of two vpc ids | `map(string)` | n/a | yes |
| aws\_peered\_region | Requester AWS Region if cluster is cross-regional | `string` | `"us-east-1"` | no |
| cidr\_blocks | A list of cidrs to whitelist in security groups | `list(string)` | `[]` | no |
| domain | Domain to be used for naming | `string` | `""` | no |
| environment | Environment | `string` | `"dev"` | no |
| instance\_type | The Instance type to launch | `string` | `"t3.small"` | no |
| key\_name | The key name to use for the instance | `string` | `"default"` | no |
| mongo\_version | Mongo Version | `string` | `"4.4"` | no |
| name | Instance Name | `string` | `"default"` | no |
| num\_suffix\_format | Numerical suffix format used as the volume and EC2 instance name suffix | `string` | `"-%d"` | no |
| root\_volume\_encrypt | Root Volume Encryption | `bool` | `true` | no |
| root\_volume\_size | Root Volume Size | `number` | `10` | no |
| tags | Tags | `map(string)` | `{}` | no |
| volume\_encrypt | EBS Volume Encryption | `bool` | `true` | no |
| volume\_iops | EBS Volume IOPS (for io1) | `number` | `100` | no |
| volume\_size | EBS Volume Size | `number` | `30` | no |
| volume\_type | EBS Volume Type | `string` | `"gp2"` | no |
| zone\_id | DNS Zone for auto-dns registration after instance creation | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| mongo\_connection\_string | Mongo Connection string example (replace password and db name) |
| mongo\_initiate\_command | Mongo Replicaset Initiate command to run |

