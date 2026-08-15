-- NAT gateway egress, attributed to the team that caused it.
--
-- This is the query that pays for the whole build.
--
-- NAT gateway charges $0.045 per GB processed, and those charges arrive in Cost
-- Explorer attached to the NAT gateway -- not to the instance, service, or team
-- that generated the traffic. There is no tag on the NAT charge that says who
-- did it. That is why NAT spend is the line item nobody can allocate.
--
-- Flow log record version 11 fixes this by embedding the instance's own tag
-- VALUE into each flow record, so the attribution is a GROUP BY rather than a
-- join against an inventory that is already out of date.
--
-- traffic_path 2 means the flow left via a NAT gateway or internet gateway.
-- Compare against query 05, which shows the same destinations reached free.
--
-- The estimated cost column uses the us-east-1 rate. Verify against
-- https://aws.amazon.com/vpc/pricing/ before quoting it at anyone.

SELECT
    instance_tag                                        AS owning_team,
    pkt_srcaddr                                         AS originating_ip,
    instance_id,
    COUNT(*)                                            AS flow_records,
    SUM(bytes)                                          AS bytes_via_nat,
    ROUND(SUM(bytes) / 1073741824.0, 4)                 AS gib_via_nat,
    ROUND(SUM(bytes) / 1073741824.0 * 0.045, 4)         AS estimated_nat_usd,
    ROUND(SUM(bytes) / 1073741824.0 * 0.045 * 30, 2)    AS projected_monthly_usd
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'ACCEPT'
  AND flow_direction = 'egress'
  AND traffic_path = 2
GROUP BY 1, 2, 3
ORDER BY bytes_via_nat DESC
LIMIT 50;
