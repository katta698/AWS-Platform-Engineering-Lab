-- The same traffic, routed two ways, priced two ways.
--
-- traffic_path tells you HOW egress left, as observed at THIS capture point:
--
--   1  another resource in the same VPC   <- includes "handed to a NAT gateway"
--   2  internet gateway or NAT gateway    <- legacy combined code, superseded
--   3  virtual private gateway
--   4  intra-region VPC peering
--   5  inter-region VPC peering
--   6  Local Zone / Wavelength Zone
--   7  gateway VPC endpoint               <- FREE
--   8  internet gateway
--
-- READ THE "as observed at THIS capture point" PART CAREFULLY. It is the thing
-- that makes this field easy to misread, and it cost this build a rewrite:
--
--   * An instance sending to the internet through a NAT gateway records
--     traffic_path 1, because from that ENI the next thing is another resource
--     in the same VPC.
--   * The NAT gateway's own ENI then records traffic_path 8 for the same
--     logical traffic -- but with no instance tag, because a NAT gateway is not
--     an instance.
--   * traffic_path 2 did not appear at all in real data on this build. Treat it
--     as a legacy value that 7 and 8 have largely replaced, not as the value to
--     filter on.
--
-- So the same bytes are visible twice, at two hops, and only ONE of those rows
-- can be attributed to a team. That is why query 04 uses the v11 next-hop field
-- rather than traffic_path.
--
-- What this query IS good for: seeing the free path and the billed path side by
-- side. Traffic to S3 takes path 7 through the gateway endpoint and costs
-- nothing; the same traffic without that endpoint would go out through the NAT
-- and cost $0.045/GB. That contrast is an argument anyone can act on.

SELECT
    traffic_path,
    CASE traffic_path
        WHEN 1 THEN 'same VPC -- often means handed to a NAT gateway (see next_hop)'
        WHEN 2 THEN 'internet/NAT gateway (legacy combined code)'
        WHEN 3 THEN 'virtual private gateway'
        WHEN 4 THEN 'intra-region VPC peering'
        WHEN 5 THEN 'inter-region VPC peering'
        WHEN 6 THEN 'Local Zone / Wavelength'
        WHEN 7 THEN 'gateway VPC endpoint    -- FREE'
        WHEN 8 THEN 'internet gateway        -- egress leaving the VPC'
        ELSE 'unclassified'
    END                                         AS path_description,
    interface_type                              AS captured_at,
    next_hop_interface_type                     AS next_hop,
    pkt_dst_aws_service                         AS destination_service,
    url_decode(instance_tag)                    AS owning_team,
    COUNT(*)                                    AS flow_records,
    SUM(bytes)                                  AS total_bytes,
    ROUND(SUM(bytes) / 1048576.0, 3)            AS total_mib,
    -- Only the NAT-bound hop is billable, and only once. Costing every row that
    -- mentions a NAT would double-count the same bytes at two capture points.
    ROUND(CASE WHEN next_hop_interface_type = 'nat_gateway'
               THEN SUM(bytes) / 1073741824.0 * 0.045
               ELSE 0 END, 6)                   AS estimated_nat_usd
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'ACCEPT'
  AND flow_direction = 'egress'
GROUP BY 1, 3, 4, 5, 6
ORDER BY total_bytes DESC;
