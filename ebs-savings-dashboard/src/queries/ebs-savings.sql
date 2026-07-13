-- EBS Volume Cleanup Savings by Month and Account
-- Source: AWS CUR 2.0 via Amazon Athena
-- Reference: https://docs.aws.amazon.com/cur/latest/userguide/cur-query-athena.html

SELECT
  DATE_FORMAT(line_item_usage_start_date, '%Y-%m')  AS month,
  line_item_usage_account_id                         AS account_id,
  bill_payer_account_id                              AS payer_account_id,
  product_region                                     AS region,
  line_item_usage_type                               AS volume_type,
  resource_tags_user_environment                     AS environment,
  resource_tags_user_team                            AS team,
  SUM(line_item_usage_amount)                        AS gb_provisioned,
  SUM(line_item_unblended_cost)                      AS total_cost,
  COUNT(DISTINCT line_item_resource_id)              AS volume_count
FROM cur_db.cost_and_usage
WHERE
  line_item_product_code    = 'AmazonEC2'
  AND line_item_usage_type  LIKE '%EBS:VolumeUsage%'
  AND line_item_line_item_type NOT IN ('Credit', 'Refund')
  AND line_item_usage_start_date
      BETWEEN DATE_ADD('month', -6, CURRENT_DATE) AND CURRENT_DATE
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY month DESC, total_cost DESC;
