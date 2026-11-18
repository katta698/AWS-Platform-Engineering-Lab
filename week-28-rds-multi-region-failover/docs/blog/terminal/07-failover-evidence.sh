# Who called the promotion, from CloudTrail. The caller is the Region switch
# execution identity, not a person: the plan did it.

aws cloudtrail lookup-events --region us-west-2 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PromoteReadReplica \
  --start-time 2026-11-18T04:00:00Z --end-time 2026-11-18T06:30:00Z \
  --query 'Events[].[EventTime,EventName,Username]' --output text

# What RDS recorded, in its own event log.

aws rds describe-events --region us-west-2 \
  --source-identifier week28-failover-replica --source-type db-instance \
  --duration 1440 \
  --query 'Events[?Date>=`2026-11-18T05:14:00Z`].[Date,Message]' --output text
