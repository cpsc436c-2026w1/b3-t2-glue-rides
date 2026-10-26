import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# Job parameters: --MONTH 2024-03 --DATABASE tutorial
args = getResolvedOptions(sys.argv, ["JOB_NAME", "MONTH", "DATABASE"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

LAKE = "s3://436c-l6-bench-940482406111/lake/rides"
# glue_catalog is this job's name for your Glue Data Catalog (set in the job's Spark settings);
# Athena shows the same table as tutorial.rides_month
TABLE = f"glue_catalog.{args['DATABASE']}.rides_month"

# 1. Read one month of trips (the original monthly Parquet file) and the zone lookup (CSV with a header row)
trips = spark.read.parquet(f"{LAKE}/flat/fhvhv_{args['MONTH']}.parquet")
zones = spark.read.option("header", "true").csv(f"{LAKE}/sources/zones_csv/")

# 2. Keep the columns the report needs and add the pickup borough from the zone lookup
zones = zones.select(
    F.col("LocationID").cast("bigint").alias("pulocationid"),
    F.col("Borough").alias("pickup_borough"),
)
rides = trips.select(
    "hvfhs_license_num", "pickup_datetime", "dropoff_datetime", "pulocationid", "dolocationid",
    "trip_miles", "base_passenger_fare", "tips", "driver_pay",
).join(zones, on="pulocationid", how="left")

# 32 Spark partitions, one task each, so the write runs in parallel
rides = rides.repartition(32)

# 3. Write the rows into an Iceberg table in your own catalog, partitioned by day of pickup.
#    The first run creates the table; every later run appends to it.
spark.sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{args['DATABASE']}")
exists = spark.sql(f"SHOW TABLES IN glue_catalog.{args['DATABASE']} LIKE 'rides_month'").count() > 0
if exists:
    rides.writeTo(TABLE).append()
else:
    (rides.writeTo(TABLE)
        .partitionedBy(F.days("pickup_datetime"))
        .tableProperty("format-version", "2")                  # Iceberg format version 2: needed for row-level deletes and MERGE
        .tableProperty("write.distribution-mode", "none")   # each task writes its rows as they come, with no regrouping by day first
        .tableProperty("write.spark.fanout.enabled", "true")   # lets each task write to many day partitions without sorting first
        .create())

job.commit()   # tells Glue the run finished (job bookmarks are saved here); the Iceberg commit happened in the write above
