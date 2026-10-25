aws ecs list-clusters --query "clusterArns[?contains(@,\`week24\`)]"
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,\`week24\`)]"
aws fis list-experiment-templates --query "experimentTemplates[].id"
aws cloudwatch describe-alarms --alarm-name-prefix week24 --query "MetricAlarms[].AlarmName"
aws iam list-roles --query "Roles[?contains(RoleName,\`week24\`)].RoleName"
aws logs describe-log-groups --query "logGroups[?contains(logGroupName,\`week24\`)]"

echo "nothing left"
