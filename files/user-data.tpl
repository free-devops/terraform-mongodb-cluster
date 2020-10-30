#!/bin/bash -xe

# 1. Install Packages
curl -fsSL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb
curl -fsSL https://www.mongodb.org/static/pgp/server-${mongo_version}.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/${mongo_version} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${mongo_version}.list
apt update -y
apt install mongodb-org awscli jq net-tools -y
dpkg -i -E ./amazon-cloudwatch-agent.deb

# 2. Populate Instance Metadata
IR="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"
EC2_INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
EC2_INSTANCE_TYPE="$(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
EC2_INSTANCE_NAME="$(aws ec2 describe-tags --region $IR --filters "Name=resource-id,Values=$EC2_INSTANCE_ID" "Name=key,Values=Name" --query 'Tags[*].Value' --output text)"

# 3. Tag instance notready
aws ec2 create-tags --resources $EC2_INSTANCE_ID --tags 'Key=Mongo,Value=notready' --region $IR

apt upgrade -y # take those updates for security's sake

# 4. Mount disc
for disc in xvdh; do

if [[ "$${disc}" == "xvdh" ]]; then dir="/data/db"; label="mongodb"; fi

DATA_STATE="unknown"
  until [ "$${DATA_STATE}" == "attached" ]; do
    DATA_STATE="$(aws ec2 describe-volumes \
              --region $${IR} \
              --filters \
              Name=attachment.instance-id,Values="$${EC2_INSTANCE_ID}" \
              Name=attachment.device,Values=/dev/"$${disc}" \
              --query Volumes[].Attachments[].State \
              --output text)"
    sleep 5
  done

  mkdir -p $${dir}

  if [[ "$${EC2_INSTANCE_TYPE}" =~ t3|t4|c5|c6|m5|m6|r5|r6 ]]; then
    VOLUME_ID="$(aws ec2 describe-volumes --region $${IR} --filters Name=attachment.instance-id,Values="$${EC2_INSTANCE_ID}" Name=attachment.device,Values=/dev/$${disc} --query Volumes[].VolumeId --output text)"
    VOLUME_SERIAL="$(echo $VOLUME_ID | sed -e 's/-//g')"
    disc="$(lsblk -o NAME,SERIAL | grep -e $VOLUME_SERIAL | awk '{ print $1 }')"
  fi

  blkid "$(readlink -f /dev/"$${disc}")" || mkfs -t xfs "$(readlink -f /dev/"$${disc}")"

  chown ubuntu.ubuntu "$${dir}" -R

  xfs_admin -L $${label} "$(readlink -f /dev/"$${disc}")"

  sed  -e "/^[\/][^ \t]*[ \t]*$${label}[ \t]/d" /etc/fstab

  grep -q ^LABEL=$${label} /etc/fstab || echo "LABEL=$${label} $${dir} xfs defaults" >> /etc/fstab

  grep -q "^$(readlink -f /dev/"$${disc}") "$${dir}" " /proc/mounts || mount "$${dir}"

done

hostnamectl set-hostname $${EC2_INSTANCE_NAME}

# 5. Configure and start mongod
cat << EOF > /etc/mongod.conf
storage:
  dbPath: /data/db
  journal:
    enabled: true
  engine: wiredTiger
  wiredTiger:
    collectionConfig:
      blockCompressor: none
# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# network interfaces
net:
  port: 27017
  bindIp: 0.0.0.0

# replication
replication:
   replSetName: rs0
security:
  authorization: enabled
  keyFile:  /etc/mongo-key
EOF

echo ${mongo_key} > /etc/mongo-key
chmod 400 /etc/mongo-key
chown mongodb:mongodb /etc/mongo-key /data/db

systemctl start mongod.service
systemctl enable mongod.service


# 6. Wait for mongo service and Tag instance ready
until nc -z 127.0.0.1 27017; do
    echo "Waiting for mongo service"
    sleep 1
done

aws ec2 create-tags --resources $EC2_INSTANCE_ID --tags 'Key=Mongo,Value=ready' --region $IR


# 7. Instantiate cluster
if [[ "$${EC2_INSTANCE_NAME}" == ${instance_name} && "$${IR}" == ${region}  ]]; then
  until [ "$${#INSTANCE_STATUS[@]}" == ${instance_count}  ]; do
    INSTANCE_STATUS=( $(for r in ${region} ${peered_region}; do aws ec2 describe-instances --filters 'Name=instance-state-name,Values=running' 'Name=tag:Mongo,Values=ready' 'Name=tag:Name,Values=${name}' --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value[][]' --region $r --output text;done))
      echo "NOT READY"
      sleep 5
  done
  MONGO_INITIATE="$(echo $${INSTANCE_STATUS[@]}|jq -R 'split(" ")| to_entries|{"_id": "rs0", "members": map({"host": (.value + ":27017"), "_id": .key, "priority": (if .key == 0 then 10 elif .key == 1 then 5 elif .key == 2 then 5 else 1 end)})}')"
  mongo --eval "rs.initiate($MONGO_INITIATE)"
  sleep 20 # To wait to cluster set down and choose master
  mongo admin --eval 'db.createUser(
  {
    user: "admin",
    pwd: "${mongo_pass}",
    roles: [    { "role": "__system",              db: "admin" },
                { "role": "backup",                db: "admin" },
                { "role": "clusterAdmin",          db: "admin" },
                { "role": "clusterManager",        db: "admin" },
                { "role": "clusterMonitor",        db: "admin" },
                { "role": "dbAdmin",               db: "admin" },
                { "role": "dbAdminAnyDatabase",    db: "admin" },
                { "role": "dbOwner",               db: "admin" },
                { "role": "enableSharding",        db: "admin" },
                { "role": "hostManager",           db: "admin" },
                { "role": "read",                  db: "admin" },
                { "role": "readAnyDatabase",       db: "admin" },
                { "role": "readWrite",             db: "admin" },
                { "role": "readWriteAnyDatabase",  db: "admin" },
                { "role": "restore",               db: "admin" },
                { "role": "root",                  db: "admin" },
                { "role": "userAdmin",             db: "admin" },
                { "role": "userAdminAnyDatabase",  db: "admin" }
            ]
  }
)'
fi

# TODO monitoring with collectd or whatever