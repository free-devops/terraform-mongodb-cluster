locals {
  instance_ips = flatten([module.ec2_cluster_first.private_ip, module.ec2_cluster_second.private_ip])
  initiate = jsonencode({_id: "rs0", members: [
  for i in local.instance_ips:
  {_id: index(local.instance_ips, i), host: "${i}:27017"}
  ]})
}

output "mongo_initiate_command" {
  description = "Mongo Replicaset Initiate command to run"
  value = "rs.initiate(${local.initiate})"
}

output "mongo_connection_string" {
  description = "Mongo Connection string example (replace password and db name)"
  value = "mongodb://admin:PASS@${join(",", local.instance_ips)}:27017/DB_NAME?replicaSet=rs0&authSource=admin"
  }