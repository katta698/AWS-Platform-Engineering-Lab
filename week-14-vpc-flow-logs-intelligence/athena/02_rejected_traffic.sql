-- Rejected traffic, clustered by source.
--
-- A REJECT is not evidence of an attack. It is equally often a health check
-- pointed at a port that moved, a security group somebody tightened on Friday,
-- or a decommissioned client that nobody told. Treating every reject as a
-- security event is how teams learn to ignore the signal entirely.
--
-- What makes a reject interesting is repetition and spread, which is what this
-- groups for. A single reject is noise. The same source rejected two thousand
-- times across forty ports is not.
--
-- reject_reason is a v8 field: BPA means VPC Block Public Access dropped it,
-- EC means VPC encryption controls did. A '-' means the ordinary case -- a
-- security group or NACL said no.

SELECT
    srcaddr                                   AS source_ip,
    dstaddr                                   AS destination_ip,
    COUNT(*)                                  AS reject_count,
    COUNT(DISTINCT dstport)                   AS distinct_ports_tried,
    ARRAY_JOIN(ARRAY_AGG(DISTINCT CAST(dstport AS VARCHAR) ORDER BY CAST(dstport AS VARCHAR)), ', ') AS ports_sample,
    ARRAY_JOIN(ARRAY_AGG(DISTINCT reject_reason), ', ') AS reject_reasons,
    MIN(from_unixtime(start))                 AS first_seen,
    MAX(from_unixtime("end"))                 AS last_seen
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '1' day, '%Y-%m-%d')
  AND action = 'REJECT'
GROUP BY 1, 2
HAVING COUNT(*) > 5
ORDER BY reject_count DESC
LIMIT 100;
