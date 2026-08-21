-- CONSOLE SIGN-IN WITHOUT MFA -- should be zero.
--
-- A successful interactive sign-in with no second factor. Every credential-theft
-- path ends at this event, so it is one of the few things worth alarming on with
-- a fixed threshold rather than a learned baseline.
--
-- Three details that make this query easy to get wrong:
--
--   1. FEDERATED SIGN-INS ARE NOT MFA-LESS SIGN-INS, and this is the one that
--      actually bites. IAM Identity Center, SAML and any external IdP satisfy
--      MFA at the IDENTITY PROVIDER, then federate into the console. Nothing
--      happens at the AWS sign-in step, so CloudTrail records MFAUsed = "No" on
--      a login that was fully MFA-protected. CloudTrail cannot see the IdP's
--      decision.
--
--      Counting those rows means alarming on every normal login in any estate
--      using Identity Center -- the setup AWS recommends. This query therefore
--      scopes to IAMUser and Root, the two principal types where the MFA field
--      is genuinely meaningful. The federated logins are still visible via the
--      companion query below; they are just not treated as findings.
--
--   2. MFAUsed from additionalEventData is the field to read, not
--      sessioncontext.attributes.mfaauthenticated. A root or IAM-user console
--      login has no assumed-role session context at all, so mfaauthenticated is
--      NULL even when a second factor was used. Both are STRINGS, never
--      booleans -- `WHERE ... = false` is a type error.
--
--   3. Sign-in events are global and are recorded in us-east-1 regardless of
--      where the user is. A query scoped to another region finds nothing and
--      looks like a clean result.

SELECT
    eventtime,
    account,
    useridentity.type                                 AS principal_type,
    COALESCE(useridentity.username, useridentity.arn) AS who,
    sourceipaddress,
    useragent,
    json_extract_scalar(additionaleventdata, '$.MFAUsed') AS mfa_used
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND eventsource = 'signin.amazonaws.com'
  AND eventname   = 'ConsoleLogin'
  AND responseelements LIKE '%Success%'
  -- Principal types where MFAUsed reflects a decision AWS actually made.
  AND useridentity.type IN ('IAMUser', 'Root')
  AND COALESCE(json_extract_scalar(additionaleventdata, '$.MFAUsed'), 'No') <> 'Yes'
ORDER BY eventtime DESC
LIMIT 100;

-- COMPANION: who is signing in via federation, and from where.
--
-- Not a finding, and deliberately not alarmed -- but this is the population the
-- query above excludes, and you should be able to see it rather than take on
-- faith that excluding it was safe. If an IdP is misconfigured, the evidence is
-- at the IdP, not here.
--
-- SELECT eventtime, useridentity.arn AS who, sourceipaddress
-- FROM ${table}
-- WHERE year  = date_format(current_date, '%Y')
--   AND month = date_format(current_date, '%m')
--   AND eventname = 'ConsoleLogin'
--   AND useridentity.type NOT IN ('IAMUser', 'Root')
-- ORDER BY eventtime DESC
-- LIMIT 100;
