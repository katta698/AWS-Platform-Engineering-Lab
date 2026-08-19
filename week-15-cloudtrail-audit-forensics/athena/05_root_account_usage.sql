-- ROOT ACCOUNT USAGE -- should be zero.
--
-- The root user can do things no IAM policy can restrict, cannot be constrained
-- by an SCP in its own account, and has no business being used for day-to-day
-- work. A handful of tasks genuinely require it (closing the account, changing
-- the support plan), so the honest expectation is "rare and explainable", not
-- "impossible".
--
-- Alarmed on a STATIC threshold of zero, deliberately. Anomaly detection would
-- learn whatever rate of root usage exists and stop reporting it -- which is the
-- opposite of what you want from a signal like this. See the monitoring module.
--
-- `AwsServiceEvent` is excluded because AWS itself emits some events attributed
-- to root that no human performed.

SELECT
    eventtime,
    account,
    region,
    eventname,
    eventsource,
    sourceipaddress,
    useragent,
    errorcode,
    -- Whether the root session was MFA-protected. Root usage without MFA is a
    -- materially worse finding than root usage with it.
    useridentity.sessioncontext.attributes.mfaauthenticated AS mfa_used
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND useridentity.type = 'Root'
  AND eventtype <> 'AwsServiceEvent'
ORDER BY eventtime DESC
LIMIT 100;
