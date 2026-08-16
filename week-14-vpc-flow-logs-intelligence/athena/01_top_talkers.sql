-- Top talkers: which source/destination pairs moved the most bytes.
--
-- The first question asked in almost every "why is the network bill up" or
-- "what is this host doing" conversation.
--
-- Note srcaddr vs pkt_srcaddr. For anything egressing through a NAT gateway,
-- srcaddr is the address seen at the capture point and pkt_srcaddr is the
-- original sender. Reading only srcaddr in a NAT'd VPC gives an answer that
-- looks perfectly reasonable and is wrong -- every flow appears to come from
-- the NAT. Both are selected here so the difference is visible rather than
-- assumed.
--
-- Partition filter is not optional: without it this scans every hour ever
-- delivered, and Athena bills $5/TB scanned.

SELECT
    pkt_srcaddr                     AS original_source,
    srcaddr                         AS observed_source,
    dstaddr                         AS destination,
    dstport                         AS destination_port,
    -- Tag values arrive percent-encoded ('-' as %2D); decode or the values are wrong.
    url_decode(instance_tag)        AS owning_team,
    COUNT(*)                        AS flow_records,
    SUM(packets)                    AS total_packets,
    SUM(bytes)                      AS total_bytes,
    ROUND(SUM(bytes) / 1048576.0, 2) AS total_mib
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'ACCEPT'
GROUP BY 1, 2, 3, 4, 5
ORDER BY total_bytes DESC
LIMIT 50;
