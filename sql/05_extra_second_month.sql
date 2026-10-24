-- Extra exercise 1: a second month. Start the job for April in CloudShell first (the README has the command).

SELECT substr(cast(partition.pickup_datetime_day AS varchar), 1, 7) AS month,
       sum(file_count) AS files, sum(record_count) AS rows
FROM tutorial."rides_month$partitions"
GROUP BY 1 ORDER BY 1;
-- Files per month for March and April.

-- Before you run it: which month will OPTIMIZE rewrite, and about how much will it read?
OPTIMIZE tutorial.rides_month REWRITE DATA USING BIN_PACK;

-- Run the first query again.
