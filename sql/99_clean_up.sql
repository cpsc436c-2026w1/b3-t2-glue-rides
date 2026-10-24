-- Clean up. For an Iceberg table, DROP TABLE also deletes its data files.
DROP TABLE IF EXISTS tutorial.zone_changes;
DROP TABLE IF EXISTS tutorial.zones;
DROP TABLE IF EXISTS tutorial.rides_month;
-- Then delete the job in CloudShell: aws glue delete-job --job-name rides-month
