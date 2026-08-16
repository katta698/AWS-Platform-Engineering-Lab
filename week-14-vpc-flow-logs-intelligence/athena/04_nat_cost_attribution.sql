-- NAT gateway egress, attributed to the team that caused it.
--
-- This is the query that pays for the whole build.
--
-- NAT gateway charges $0.045 per GB processed, and those charges arrive in Cost
-- Explorer attached to the NAT gateway -- not to the instance, service, or team
-- that generated the traffic. There is no tag on the NAT charge that says who
-- did it. That is why NAT spend is the line item nobody can allocate.
--
-- TWO THINGS HERE WERE ONLY LEARNED FROM REAL DELIVERED DATA:
--
-- 1. `traffic_path = 2` DOES NOT WORK for this, and the first version of this
--    query returned zero rows because of it. The documented meaning of 2 is
--    "through an internet gateway or NAT gateway", but that is not what appears
--    in practice. Measured at the SENDING INSTANCE's own ENI, traffic heading to
--    a NAT gateway is just traffic to another resource in the same VPC --
--    traffic_path 1. The value 8 (internet gateway) shows up separately on the
--    NAT gateway's OWN ENI, where there is no instance tag to attribute to.
--    So traffic_path can tell you a NAT was involved somewhere, but it cannot
--    tell you WHOSE traffic it was.
--
-- 2. The record version 11 field `next_hop_interface_type` is what actually
--    solves it. It states, on the sender's own record, that the next hop is a
--    nat_gateway -- so the instance's tag and the NAT destination are on the
--    SAME ROW. No join, no inference from route tables.
--
-- Tag values are percent-encoded in flow log records (a '-' arrives as %2D), so
-- every tag column has to go through url_decode or the values are wrong and the
-- grouping splits.
--
-- The estimated cost column uses the us-east-1 rate. Verify against
-- https://aws.amazon.com/vpc/pricing/ before quoting it at anyone.

SELECT
    url_decode(instance_tag)                            AS owning_team,
    pkt_srcaddr                                         AS originating_ip,
    instance_id,
    next_hop_interface_id                               AS via_nat_eni,
    COUNT(*)                                            AS flow_records,
    SUM(bytes)                                          AS bytes_via_nat,
    ROUND(SUM(bytes) / 1073741824.0, 6)                 AS gib_via_nat,
    ROUND(SUM(bytes) / 1073741824.0 * 0.045, 6)         AS estimated_nat_usd,
    ROUND(SUM(bytes) / 1073741824.0 * 0.045 * 30, 4)    AS projected_monthly_usd
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND flow_direction = 'egress'
  -- The v11 field. This is the whole trick.
  AND next_hop_interface_type = 'nat_gateway'
GROUP BY 1, 2, 3, 4
ORDER BY bytes_via_nat DESC
LIMIT 50;
