# Nothing left in either region, asked of the API rather than read from the
# destroy output. Snapshots are included because they outlive a destroyed
# instance and keep charging.

aws rds describe-db-instances --region us-east-1 \
  --query 'DBInstances[?starts_with(DBInstanceIdentifier,`week28`)].DBInstanceIdentifier'

aws rds describe-db-instances --region us-west-2 \
  --query 'DBInstances[?starts_with(DBInstanceIdentifier,`week28`)].DBInstanceIdentifier'

aws rds describe-db-snapshots --region us-west-2 --snapshot-type manual \
  --query 'DBSnapshots[?starts_with(DBInstanceIdentifier,`week28`)].DBSnapshotIdentifier'

# The $70/month line item.

aws arc-region-switch list-plans --region us-east-1 \
  --query 'plans[?name==`week28-failover`].name'
