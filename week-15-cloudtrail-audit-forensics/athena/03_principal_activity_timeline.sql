-- WHAT DID THIS PRINCIPAL DO?
--
-- The second forensic question. Once query 02 tells you who made a change, this
-- shows everything else that identity did in the same window -- which is usually
-- where the story is. A single deletion is an incident; the same identity
-- touching nine other things around it is a different incident entirely.
--
-- Handles the identity shape that trips people up. A human using the console
-- appears as an IAM user or an SSO role session; an automated pipeline appears
-- as an assumed role. For a role session, `useridentity.username` is often null
-- and the useful name lives in
-- `useridentity.sessioncontext.sessionissuer.username`. Querying only the top
-- level silently misses every role-based action, which in a Terraform-driven
-- account is nearly all of them.
--
-- EDIT the principal fragment below.

SELECT
    eventtime,
    account,
    region,
    eventsource,
    eventname,
    readonly,
    sourceipaddress,
    useragent,
    errorcode,
    errormessage
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  -- >>> EDIT: username, role name or ARN fragment <<<
  AND (
        useridentity.arn      LIKE '%REPLACE_WITH_PRINCIPAL%'
     OR useridentity.username LIKE '%REPLACE_WITH_PRINCIPAL%'
     OR useridentity.sessioncontext.sessionissuer.username LIKE '%REPLACE_WITH_PRINCIPAL%'
  )
ORDER BY eventtime DESC
LIMIT 200;
