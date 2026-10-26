-- Step 2: check what the job built. Data source: AwsDataCatalog.

SELECT count(*) AS files, round(avg(file_size_in_bytes) / 1e6, 1) AS avg_mb, sum(record_count) AS rows
FROM tutorial."rides_month$files";
-- Compare the file count with your prediction for files per day (March has 31 days).

-- The next two statements let you predict the week report's Data scanned from the files' column sizes.
DESCRIBE tutorial.rides_month;
-- Count down the list from 1 to get each column's field id. In our run, pickup_datetime was 3,
-- base_passenger_fare 7 and pickup_borough 10.

-- Athena's "$files" table has no partition column, so this query picks the week's files by their path.
-- column_sizes maps a field id to the bytes that column takes in each file.
SELECT round(sum(column_sizes[3] + column_sizes[7] + column_sizes[10]) / 1e6, 1) AS three_columns_mb,
       round(sum(column_sizes[7] + column_sizes[10]) / 1e6, 1) AS fare_and_borough_mb
FROM tutorial."rides_month$files"
WHERE regexp_like(file_path, 'pickup_datetime_day=2024-03-1[0-6]/');

-- The week report reads pickup_datetime, base_passenger_fare and pickup_borough for 10 to 16 March.
-- Before you run it, decide whether its Data scanned will be close to three_columns_mb, close to
-- fare_and_borough_mb, or far from both. Then note the run time and Data scanned under the results.
-- You run it again after Step 4.
SELECT pickup_borough, count(*) AS trips, round(avg(base_passenger_fare), 2) AS avg_fare
FROM tutorial.rides_month
WHERE pickup_datetime >= TIMESTAMP '2024-03-10 00:00:00'
  AND pickup_datetime <  TIMESTAMP '2024-03-17 00:00:00'
GROUP BY pickup_borough
ORDER BY trips DESC;
