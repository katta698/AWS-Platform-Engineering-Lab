# The fence, before anything is built.
# Lambda concurrency is per account AND per region. This week exhausts the
# pool on purpose, so it runs where there is nothing else to starve.

echo "--- us-east-1: where the other projects live ---"
aws lambda list-functions --region us-east-1 --query 'length(Functions)'
aws lambda get-account-settings --region us-east-1 --query 'AccountLimit.ConcurrentExecutions'

echo "--- us-east-2: the empty region this lab will use ---"
aws lambda list-functions --region us-east-2 --query 'length(Functions)'
aws lambda get-account-settings --region us-east-2 --query 'AccountLimit.ConcurrentExecutions'
