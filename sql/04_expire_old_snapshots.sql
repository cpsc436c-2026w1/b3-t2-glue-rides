-- Step 5: remove the old files for good. Count the files in S3 first (the README has the command).

SELECT snapshot_id, operation FROM tutorial."rides_month$snapshots" ORDER BY committed_at;
-- Copy the snapshot_id of the append (the job's load).

-- Paste it as a number.
SELECT count(*) FROM tutorial.rides_month FOR VERSION AS OF <snapshot_id of the append>
WHERE base_passenger_fare < 0;
-- The rides you deleted in Step 3: an older snapshot still reads them.

ALTER TABLE tutorial.rides_month SET TBLPROPERTIES ('vacuum_max_snapshot_age_seconds' = '60');
SHOW TBLPROPERTIES tutorial.rides_month;
-- A table property, kept in the table's metadata file. The default is five days; 60 seconds is only for this tutorial.

-- Before you run it: which snapshots will be left, and how many files will S3 hold?
VACUUM tutorial.rides_month;

SELECT snapshot_id, operation FROM tutorial."rides_month$snapshots";
-- If more than one snapshot is left, wait a minute, run VACUUM again, and list the snapshots again.

SELECT count(*) FROM tutorial.rides_month FOR VERSION AS OF <snapshot_id of the append>;
-- Once the append is expired, this fails: "Iceberg snapshot ID does not exists".

-- Then count the files in S3 again.
