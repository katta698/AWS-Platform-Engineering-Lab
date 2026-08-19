-- Run this FIRST, before trusting any other query in this folder.
--
-- Partition projection fails silently. If the storage.location.template does not
-- match the delivered S3 prefixes exactly -- a wrong segment, a missing
-- zero-pad, an account not in the enum -- every query returns zero rows and
-- reports SUCCEEDED. There is no error state to notice, and an audit dashboard
-- built on top would show a reassuring flat zero forever.
--
-- The organization-trail layout has five projected keys and more ways to be
-- subtly wrong than the single-account layout AWS documents:
--
--   AWSLogs/<org-id>/<account>/CloudTrail/<region>/<year>/<month>/<day>/
--
-- Expected: one row per account that has been active, with a recent max_event_time.
--
-- If this returns nothing while objects are visibly present in the bucket,
-- compare the analytics module's storage_location_template output against a real
-- key from:
--
--   aws s3 ls s3://<bucket>/AWSLogs/ --recursive | tail -5
--
-- Do not debug this by re-reading the Terraform. Compare the two strings.

SELECT
    account,
    region,
    COUNT(*)                          AS events,
    COUNT(DISTINCT eventname)         AS distinct_actions,
    COUNT(DISTINCT useridentity.arn)  AS distinct_principals,
    MIN(eventtime)                    AS earliest_event,
    MAX(eventtime)                    AS latest_event
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
GROUP BY account, region
ORDER BY events DESC;
