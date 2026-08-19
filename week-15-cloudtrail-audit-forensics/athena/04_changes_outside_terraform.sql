-- WHAT CHANGED OUTSIDE TERRAFORM?
--
-- Infrastructure-as-code only tells the truth if nobody edits around it. This
-- finds mutating changes that did NOT come from the Terraform run role -- the
-- console clicks and CLI calls that produce drift, and that Terraform will
-- either silently revert or trip over on the next apply.
--
-- Real example from this lab: in Week 10 an EventBridge rule was disabled with
-- the CLI to stop it costing pennies. That change was invisible to the code, and
-- the module still declared the rule ENABLED. This query is how you find that
-- class of change before an apply does.
--
-- The signal is `useragent`. Terraform runs through HCP arrive with an
-- APN/HashiCorp agent string; console actions carry a console user agent; CLI
-- actions carry aws-cli. Filtering on user agent rather than principal matters
-- because the same role can be used both ways -- an engineer assuming the
-- automation role and clicking in the console looks identical by principal and
-- completely different by user agent.

SELECT
    eventtime,
    account,
    region,
    eventsource,
    eventname,
    COALESCE(
        useridentity.username,
        useridentity.sessioncontext.sessionissuer.username,
        useridentity.arn
    )                                   AS who,
    useragent,
    sourceipaddress
FROM ${table}
WHERE year  = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND readonly = 'false'
  -- Not Terraform
  AND useragent NOT LIKE '%APN/1.0 HashiCorp%'
  AND useragent NOT LIKE '%Terraform%'
  -- Not the AWS services acting on their own behalf. Without this the results
  -- are dominated by autoscaling, config and other service principals doing
  -- exactly what they are supposed to.
  AND useridentity.type <> 'AWSService'
  AND eventsource NOT IN ('cloudtrail.amazonaws.com')
ORDER BY eventtime DESC
LIMIT 200;
