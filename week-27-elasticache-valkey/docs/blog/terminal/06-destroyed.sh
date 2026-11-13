# Nothing left, asked of the API rather than read from the destroy output.

aws elasticache describe-serverless-caches --region us-east-1 \
  --query 'ServerlessCaches[?starts_with(ServerlessCacheName,`week27`)].ServerlessCacheName'

aws lambda list-functions --region us-east-1 \
  --query 'length(Functions[?starts_with(FunctionName,`week27`)])'
