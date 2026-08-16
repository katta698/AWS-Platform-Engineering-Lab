-- Which intermediate resource actually handled each flow.
--
-- The next-hop fields are record version 11 and are new enough that most
-- documentation predates them. Before they existed, answering "did this go via
-- the NAT gateway or the endpoint" meant inferring it from route tables and
-- hoping the route table had not changed since. Now the record says so directly.
--
-- interface_type / next_hop_interface_type resolve to one of:
--   nat_gateway | regional_nat_gateway | network_load_balancer |
--   transit_gateway | vpc_endpoint      (or '-' when not applicable)
--
-- This is the query for "traffic is reaching somewhere it should not -- which
-- hop let it through", and for confirming an endpoint is actually being used
-- after you add one, rather than assuming the route took effect.

SELECT
    interface_type                  AS capture_interface_type,
    next_hop_interface_type         AS next_hop_type,
    next_hop_interface_id           AS next_hop_eni,
    next_hop_vpc_id                 AS next_hop_vpc,
    flow_direction,
    url_decode(instance_tag)        AS owning_team,
    pkt_dst_aws_service             AS destination_service,
    COUNT(*)                        AS flow_records,
    SUM(bytes)                      AS total_bytes
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND next_hop_interface_id <> '-'
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY total_bytes DESC
LIMIT 100;
