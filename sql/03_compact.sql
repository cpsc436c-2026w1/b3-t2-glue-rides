-- In Step 4, compact the table.

-- Before you run it, predict whether the number of current data files will stay near the count from Step 2,
-- fall to a few dozen, or increase. Will the row count stay equal to the count after the DELETE?
OPTIMIZE tutorial.rides_month REWRITE DATA USING BIN_PACK;
-- BIN_PACK combines small files into larger ones, up to a target size. This is compaction (L10).

SELECT count(*) AS files, round(avg(file_size_in_bytes) / 1e6, 1) AS avg_mb, sum(record_count) AS stored_records
FROM tutorial."rides_month$files";

SELECT operation, summary['added-data-files'] AS added, summary['deleted-data-files'] AS removed
FROM tutorial."rides_month$snapshots"
ORDER BY committed_at;

-- Now run the week report from 01_check_the_table.sql again and compare run time and Data scanned.
