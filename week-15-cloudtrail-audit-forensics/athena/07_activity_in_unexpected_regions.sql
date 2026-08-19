-- ACTIVITY IN REGIONS WE DO NOT USE -- should be zero.
--
-- Resources appearing in an unused region is a classic compromise signal: it is
-- where crypto-mining and data staging tend to show up, precisely because nobody
-- looks there. It is also, more often, someone forgetting to set --region.
--
-- This query only works because the trail is MULTI-REGION. A single-region trail
-- has no visibility into the regions you are asking about, so it would return a
-- confident empty result -- structurally unable to find what it is looking for.
-- The same applies to the table: the region projection enum must cover every
-- enabled region, not just the ones in use, or these events exist in S3 and are
-- invisible to Athena.
--
-- EDIT the expected-region list if the estate grows.

SELECT
    region,
    account,
    COUNT(*)                                          AS events,
    COUNT(DISTINCT eventname)                         AS distinct_actions,
    ARRAY_JOIN(ARRAY_AGG(DISTINCT eventsource), ', ') AS services_touched,
    MIN(eventtime)                                    AS first_seen,
    MAX(eventtime)                                    AS last_seen
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  -- >>> EDIT: regions this estate legitimately uses <<<
  AND region NOT IN ('us-east-1')
  -- Global services report into us-east-1 but carry their own region marker on
  -- some events; excluding read-only calls keeps the result to things that
  -- actually created or changed something.
  AND readonly = 'false'
  AND useridentity.type <> 'AWSService'
GROUP BY region, account
ORDER BY events DESC;
