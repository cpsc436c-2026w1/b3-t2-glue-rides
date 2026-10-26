-- In Step 5, remove the old files. Count the files in S3 first with the CloudShell command in the README.

SELECT snapshot_id, operation FROM tutorial."rides_month$snapshots" ORDER BY committed_at;
-- Copy the snapshot_id of the append, which is the job's load.

-- Replace the placeholder with that snapshot_id as a number, here and in the last query of this file.
SELECT count(*) FROM tutorial.rides_month FOR VERSION AS OF <snapshot_id of the append>
WHERE base_passenger_fare < 0;
-- This query shows that an older snapshot still reads the rides deleted in Step 3.

ALTER TABLE tutorial.rides_month SET TBLPROPERTIES ('vacuum_max_snapshot_age_seconds' = '60');
SHOW TBLPROPERTIES tutorial.rides_month;
-- This property is stored in the table's metadata file. The default is five days, and 60 seconds is only for this tutorial.

-- Before you run it, decide which older snapshots can expire once they are more than 60 seconds old.
-- Will the S3 file count drop, stay the same, or rise?
VACUUM tutorial.rides_month;

SELECT snapshot_id, operation FROM tutorial."rides_month$snapshots";
-- If more than one snapshot is left, wait a minute, run VACUUM again, and list the snapshots again.

-- The next query fails on purpose once the append is expired, with "Iceberg snapshot ID does not exists".
-- It needs the append's snapshot_id pasted in, as above. If it returns a number, VACUUM has not expired the append yet.
SELECT count(*) FROM tutorial.rides_month FOR VERSION AS OF <snapshot_id of the append>;

-- Then count the files in S3 again.
