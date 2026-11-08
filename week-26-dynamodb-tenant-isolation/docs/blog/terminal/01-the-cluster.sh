# Three DAX nodes, one per Availability Zone, in front of one pooled table.
# This is the whole cost of the week, and it meters whether or not anything
# reads from it.

aws dax describe-clusters --cluster-names week26-isolation --region us-east-1 \
  --query 'Clusters[0].{Cluster:ClusterName,Status:Status,NodeType:NodeType,Nodes:length(Nodes)}'

echo "--- one node per AZ, which is what makes it fault tolerant ---"
aws dax describe-clusters --cluster-names week26-isolation --region us-east-1 \
  --query 'Clusters[0].Nodes[].{Node:NodeId,AZ:AvailabilityZone,Status:NodeStatus}' --output table
