-- WHO DELETED OR MODIFIED THIS RESOURCE?
--
-- The query this whole week exists for.
--
-- The motivating incident is real. During Week 12 of this lab, the account's AWS
-- Config recorder was deleted mid-build by an unrelated project's cleanup script.
-- It broke the build. The recorder was rebuilt -- but the question "who deleted
-- it, and when" was never answerable by anyone, because nothing was recording
-- API actions in a form that could be queried.
--
-- Note what this does that detection tooling cannot. Security Hub and GuardDuty
-- (Week 11) report that something IS wrong. Config (Week 12) reports whether a
-- resource IS compliant. Both describe state. Only CloudTrail records the ACTION,
-- and once an auto-remediation has fixed the problem, the action record is the
-- only evidence left that it ever happened.
--
-- EDIT the two placeholders below before running:
--   the resource name/ARN fragment you are investigating, and the date window.

SELECT
    eventtime,
    account,
    region,
    eventname,
    eventsource,
    useridentity.type                             AS principal_type,
    COALESCE(
        useridentity.username,
        useridentity.sessioncontext.sessionissuer.username,
        useridentity.arn
    )                                             AS who,
    sourceipaddress,
    useragent,
    errorcode,
    -- The raw parameters are where the resource identifier actually lives. Kept
    -- as a substring because full requestparameters can be very large and this
    -- query is often run over a wide window.
    SUBSTR(requestparameters, 1, 300)             AS request_parameters
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  -- Mutating calls only. Read-only API calls dominate CloudTrail by volume and
  -- never explain why something disappeared.
  AND readonly = 'false'
  -- >>> EDIT: the resource you are investigating <<<
  AND (
        requestparameters LIKE '%REPLACE_WITH_RESOURCE_NAME%'
     OR responseelements  LIKE '%REPLACE_WITH_RESOURCE_NAME%'
  )
ORDER BY eventtime DESC
LIMIT 100;
