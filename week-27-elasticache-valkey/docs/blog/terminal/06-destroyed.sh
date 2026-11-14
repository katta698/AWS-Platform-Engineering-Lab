# Nothing left, asked of the API rather than read from the destroy output.

aws elasticache describe-serverless-caches --region us-east-1 \
  --query 'ServerlessCaches[].ServerlessCacheName'

aws lambda list-functions --region us-east-1 \
  --query 'Functions[?starts_with(FunctionName,`week27`)].FunctionName'
