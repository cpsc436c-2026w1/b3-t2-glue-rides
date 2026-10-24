-- Extra exercise 2: apply changes by key with MERGE, twice.
-- Replace <account> with your account number (your bucket is 436c-glue-<account>).

CREATE TABLE tutorial.zones
WITH (table_type = 'ICEBERG', location = 's3://436c-glue-<account>/tutorial2/warehouse/tutorial.db/zones/', is_external = false)
AS SELECT * FROM course.course_rides.zones;

SELECT count(*) FROM tutorial.zones;

CREATE TABLE tutorial.zone_changes
WITH (table_type = 'ICEBERG', location = 's3://436c-glue-<account>/tutorial2/warehouse/tutorial.db/zone_changes/', is_external = false)
AS SELECT * FROM (VALUES
    (132, 'Queens', 'JFK International Airport', 'Airports'),
    (138, 'Queens', 'LaGuardia International Airport', 'Airports'),
    (300, 'Queens', 'New test zone', 'Boro Zone'))
  AS c (locationid, borough, zone, service_zone);
-- Two of these zones exist already; one is new.

-- Before you run it: how many rows will tutorial.zones have afterwards?
MERGE INTO tutorial.zones t
USING tutorial.zone_changes c
ON t.locationid = c.locationid
WHEN MATCHED THEN UPDATE SET borough = c.borough, zone = c.zone, service_zone = c.service_zone
WHEN NOT MATCHED THEN INSERT (locationid, borough, zone, service_zone)
  VALUES (c.locationid, c.borough, c.zone, c.service_zone);

SELECT count(*) FROM tutorial.zones;

-- Before you run the same MERGE again: how many rows afterwards? Then run it and count.
