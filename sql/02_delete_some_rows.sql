-- In Step 3, delete some rows and then inspect the table, its data files and its snapshots.

SELECT count(*) FROM tutorial.rides_month WHERE base_passenger_fare < 0;
-- Note this number.

-- Before you run the DELETE, decide whether the number of data files in "rides_month$files" will go down, stay the same, or go up.
DELETE FROM tutorial.rides_month WHERE base_passenger_fare < 0;

SELECT count(*) FROM tutorial.rides_month;
-- This is the new visible row count.

SELECT count(*) AS files, sum(record_count) AS rows
FROM tutorial."rides_month$files";
-- Compare files and rows with Step 2.

SELECT operation, summary['added-delete-files'] AS delete_files
FROM tutorial."rides_month$snapshots"
ORDER BY committed_at;

-- Then count the files in S3 with the CloudShell command in the README.
