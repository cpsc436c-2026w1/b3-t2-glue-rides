-- Step 2: check what the job built. Data source: AwsDataCatalog.

SELECT count(*) AS files, round(avg(file_size_in_bytes) / 1e6, 1) AS avg_mb, sum(record_count) AS rows
FROM tutorial."rides_month$files";
-- Compare with your prediction for files per day (31 days in March).

-- The week report: note the run time and Data scanned under the results. You run it again after Step 4.
SELECT pickup_borough, count(*) AS trips, round(avg(base_passenger_fare), 2) AS avg_fare
FROM tutorial.rides_month
WHERE pickup_datetime >= TIMESTAMP '2024-03-10 00:00:00'
  AND pickup_datetime <  TIMESTAMP '2024-03-17 00:00:00'
GROUP BY pickup_borough
ORDER BY trips DESC;
