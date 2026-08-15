-- Port scan candidates: one source, many distinct destination ports, rejected.
--
-- The discriminator between a scan and a broken client is FAN-OUT. A misbehaving
-- client retries the same port forever. A scanner walks the port range. So the
-- threshold here is on COUNT(DISTINCT dstport), not on volume.
--
-- SYN-without-ACK is the other half of the signal. tcp_flags is a bitmask:
-- 2 = SYN alone, 18 = SYN-ACK. A half-open scan shows as a burst of 2s with no
-- corresponding 18 coming back. Note that flags are OR-ed together across the
-- aggregation interval, so short connections can legitimately show combined
-- values -- this is a lead, not a verdict.
--
-- On a genuinely internet-reachable address, this query returns rows within
-- minutes of exposure. Background scanning of the public IPv4 space is constant.

SELECT
    srcaddr                                     AS scanner_ip,
    dstaddr                                     AS target_ip,
    COUNT(DISTINCT dstport)                     AS distinct_ports,
    COUNT(*)                                    AS attempts,
    SUM(CASE WHEN tcp_flags = 2 THEN 1 ELSE 0 END) AS syn_only_flows,
    MIN(from_unixtime(start))                   AS first_seen,
    MAX(from_unixtime("end"))                   AS last_seen,
    date_diff('minute', MIN(from_unixtime(start)), MAX(from_unixtime("end"))) AS span_minutes
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'REJECT'
  AND flow_direction = 'ingress'
GROUP BY 1, 2
HAVING COUNT(DISTINCT dstport) >= 20
ORDER BY distinct_ports DESC, attempts DESC
LIMIT 100;
