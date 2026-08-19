-- CONSOLE SIGN-IN WITHOUT MFA -- should be zero.
--
-- A successful interactive sign-in with no second factor. Every credential-theft
-- path ends at this event, so it is one of the few things worth alarming on with
-- a fixed threshold rather than a learned baseline.
--
-- Two details that make this query easy to get wrong:
--
--   1. `mfaauthenticated` is a STRING, not a boolean. It is the text 'true' or
--      'false', and it can also be NULL. Writing `WHERE ... = false` is a type
--      error; writing `WHERE ... <> 'true'` silently drops the NULL rows, which
--      are the federated sign-ins you probably care about. Hence the explicit
--      NULL handling below.
--
--   2. Sign-in events are global and are recorded in us-east-1 regardless of
--      where the user is. A query scoped to another region finds nothing and
--      looks like a clean result.

SELECT
    eventtime,
    account,
    COALESCE(useridentity.username, useridentity.arn) AS who,
    sourceipaddress,
    useragent,
    responseelements,
    COALESCE(
        useridentity.sessioncontext.attributes.mfaauthenticated,
        'null -- federated or unknown'
    )                                                 AS mfa_authenticated
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND eventsource = 'signin.amazonaws.com'
  AND eventname   = 'ConsoleLogin'
  AND responseelements LIKE '%Success%'
  AND (
        useridentity.sessioncontext.attributes.mfaauthenticated IS NULL
     OR useridentity.sessioncontext.attributes.mfaauthenticated <> 'true'
  )
ORDER BY eventtime DESC
LIMIT 100;
