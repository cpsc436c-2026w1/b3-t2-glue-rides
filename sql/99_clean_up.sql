-- Clean up. For an Iceberg table, DROP TABLE also deletes its data files.
DROP TABLE IF EXISTS tutorial.zone_changes;
DROP TABLE IF EXISTS tutorial.zones;
DROP TABLE IF EXISTS tutorial.rides_month;
DROP DATABASE IF EXISTS tutorial;
-- Then delete the job in CloudShell with the command in the README.
