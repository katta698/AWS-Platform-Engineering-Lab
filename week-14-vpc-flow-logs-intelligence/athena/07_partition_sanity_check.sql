-- Run this FIRST, before trusting any other query in this folder.
--
-- Partition projection fails silently. If the storage.location.template does not
-- match the delivered S3 prefixes exactly -- one wrong key name, a missing
-- zero-pad, the wrong region -- every query in this workgroup returns zero rows
-- and reports SUCCEEDED. There is no error state to notice. A dashboard built on
-- top would show a flat, healthy-looking zero line forever.
--
-- So the check is: ask for data you KNOW exists and confirm it comes back.
--
-- Expected: at least one row, with a recent max_end_time and a non-zero
-- record count. If this returns nothing while objects are visibly present in
-- the bucket, the template is wrong -- compare the analytics module's
-- storage_location_template output against a real key from:
--
--   aws s3 ls s3://<bucket>/AWSLogs/ --recursive | tail -5
--
-- Do not debug this by re-reading the Terraform. Compare the two strings.

SELECT
    region,
    year,
    month,
    day,
    COUNT(*)                        AS records,
    COUNT(DISTINCT hour)            AS hours_present,
    MIN(from_unixtime(start))       AS min_start_time,
    MAX(from_unixtime("end"))       AS max_end_time,
    SUM(bytes)                      AS total_bytes,
    -- If this column is entirely '-', the delivery role is missing
    -- ec2:DescribeTags and the v11 tag fields are not resolving.
    COUNT(DISTINCT instance_tag)    AS distinct_instance_tags
FROM ${table}
WHERE concat(year, '-', month, '-', day) >= date_format(current_date - interval '2' day, '%Y-%m-%d')
GROUP BY 1, 2, 3, 4
ORDER BY year DESC, month DESC, day DESC;
