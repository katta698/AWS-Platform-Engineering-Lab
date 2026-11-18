# What the Region switch plan did, from the run's own saved measurement.

python ../../../scripts/show_failover.py

# The former replica, asked of the API: no replication source, because
# promotion cannot be undone.

aws rds describe-db-instances --db-instance-identifier week28-failover-replica \
  --region us-west-2 \
  --query 'DBInstances[].{Status:DBInstanceStatus,ReplicationSource:ReadReplicaSourceDBInstanceIdentifier}'
