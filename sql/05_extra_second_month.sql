-- In extra exercise 1, load a second month. Start the job for April in CloudShell first with the command in the README.

SELECT substr(cast(partition.pickup_datetime_day AS varchar), 1, 7) AS month,
       sum(file_count) AS files, sum(record_count) AS rows
FROM tutorial."rides_month$partitions"
GROUP BY 1 ORDER BY 1;
-- This query reports the file and row totals for each month.

-- Before you run it, predict whether OPTIMIZE will rewrite March, April, or both.
-- Will Data scanned be in the same ballpark as the March compaction, much lower, or much higher?
OPTIMIZE tutorial.rides_month REWRITE DATA USING BIN_PACK;

-- Run the first query again.
