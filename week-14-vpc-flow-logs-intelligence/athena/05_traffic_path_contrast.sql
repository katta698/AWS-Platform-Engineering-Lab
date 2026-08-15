-- The same traffic, routed two ways, priced two ways.
--
-- traffic_path tells you HOW egress left the VPC:
--
--   1  another resource in the same VPC
--   2  internet gateway or NAT gateway     <- billed $0.045/GB through NAT
--   3  virtual private gateway
--   4  intra-region VPC peering
--   5  inter-region VPC peering
--   6  Local Zone / Wavelength Zone
--   7  gateway VPC endpoint                <- FREE
--   8  internet gateway
--
-- Traffic to S3 can take path 2 or path 7 depending on nothing more than whether
-- a gateway endpoint exists on the route table. The bytes are identical. One
-- costs $0.045/GB and one costs nothing.
--
-- This is the query that turns flow logs from a security tool into a cost tool,
-- and it is the argument for adding a gateway endpoint that anyone can act on.

SELECT
    traffic_path,
    CASE traffic_path
        WHEN 1 THEN 'same VPC (another resource)'
        WHEN 2 THEN 'internet / NAT gateway  -- BILLED $0.045/GB via NAT'
        WHEN 3 THEN 'virtual private gateway'
        WHEN 4 THEN 'intra-region VPC peering'
        WHEN 5 THEN 'inter-region VPC peering'
        WHEN 6 THEN 'Local Zone / Wavelength'
        WHEN 7 THEN 'gateway VPC endpoint    -- FREE'
        WHEN 8 THEN 'internet gateway'
        ELSE 'unclassified'
    END                                         AS path_description,
    pkt_dst_aws_service                         AS destination_service,
    COUNT(*)                                    AS flow_records,
    SUM(bytes)                                  AS total_bytes,
    ROUND(SUM(bytes) / 1048576.0, 2)            AS total_mib,
    ROUND(CASE WHEN traffic_path = 2
               THEN SUM(bytes) / 1073741824.0 * 0.045
               ELSE 0 END, 4)                   AS estimated_egress_usd
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'ACCEPT'
  AND flow_direction = 'egress'
GROUP BY 1, 3
ORDER BY total_bytes DESC;
