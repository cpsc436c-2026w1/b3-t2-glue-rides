# B3T2: build and maintain a table (Glue and Athena)

This tutorial follows L11 and opens Assignment 3. Tutorial 1 gave you a first try at using and changing a lakehouse
table in Athena. Here you try the other two kinds of work A3 asks for, on the same New York rides:

- **build:** a ready Glue job (Spark) loads one month of rides, with each pickup's borough from the zone lookup, into
  an Iceberg table in your own account. You read its script and predict what it will produce.
- **maintain:** the table comes out as many small files. You delete some rows, compact the table with `OPTIMIZE`,
  expire old snapshots with `VACUUM`, and count the files in S3 after each step.

A3 asks for the same moves on the grocer data, with less given to you. The whole tutorial costs about 5 cents: one Glue
run of about 300 to 380 DPU-seconds at $0.44 per DPU-hour, plus Athena under a cent.

All course tutorials are listed on the [Tutorials page](https://cpsc436c-2026w1.github.io/lecture-reviews/tutorials.html).

## 1. Before you start

You need two earlier setups, both in Region **Canada (Central)**:

- **Tutorial 1's setup** ([b3-t1-athena-rides](https://github.com/cpsc436c-2026w1/b3-t1-athena-rides), section 1):
  the Athena result location, the Data scanned limit and the `course` data source.
- **L7's `setup_glue.sh`** ([l7-spark-glue](https://github.com/cpsc436c-2026w1/l7-spark-glue)): your bucket
  `436c-glue-<your account number>` and the Glue role `436c-glue-notebook`.

## 2. Set up the job (once)

Open **CloudShell** with the `>_` icon in the top bar and paste:

```
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/setup_t2.sh && \
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/load_rides_month.py && \
bash setup_t2.sh
```

The script lets your Glue role read the course lake, copies the job script to your bucket, and creates the Glue job
`rides-month` (Glue 5.0, two G.1X workers). It ends with:

```
job     rides-month created

Start it:  aws glue start-job-run --job-name rides-month
```

You can safely rerun it. If it stops with a line starting `STOP:`, run the setup it names first. If it fails another
way, send the error and your account number to your TA.

## 3. The steps

Run SQL in the Athena query editor with **Data source** `AwsDataCatalog`, one statement at a time. Each step's SQL is
in [`sql/`](sql/), and its comments say what to predict before you run a statement. Write each prediction down, then open
the step's box after you have run it.

### Step 1: start the job, then read it while it runs

```
aws glue start-job-run --job-name rides-month
```

The run takes about 3 minutes (Glue console, **ETL jobs**, `rides-month`, **Runs**). While it runs, open
[`load_rides_month.py`](load_rides_month.py) and write down:

1. Which line decides how the table is partitioned, and how many partitions will March have?
2. How many data files per day do you expect?
3. What would happen if the job ran a second time?

<details>
<summary>Check your predictions (open after the run)</summary>

1. `.partitionedBy(F.days("pickup_datetime"))`: one partition per day of pickup, 31 for March.
2. `repartition(32)` makes 32 Spark partitions, one task each, and the table property
   `write.distribution-mode = none` lets each task write its own rows for every day it holds: up to 32 files a day.
   Measured: 32 a day, 992 files of about 0.4 MB.
3. It appends again: the table doubles to 42,561,576 rows, two appends of 21,280,788. The script does not check what
   it already loaded. That is tutorial 1's load run twice, now in a job.
</details>

### Step 2: check what the job built

[`sql/01_check_the_table.sql`](sql/01_check_the_table.sql)

<details>
<summary>Check your predictions</summary>

992 files of 0.4 MB, 21,280,788 rows. The week report gives trips and average fare per pickup borough, a column the
job joined in from the zone lookup: the job built a table no course table has. Our run: 0.8 s and 13.1 MB scanned.
</details>

### Step 3: delete some rows

[`sql/02_delete_some_rows.sql`](sql/02_delete_some_rows.sql). Then count the table's files in S3, in CloudShell:

```
aws s3 ls s3://436c-glue-<your account number>/tutorial2/warehouse/tutorial.db/rides_month/data/ --recursive | wc -l
```

<details>
<summary>Check your predictions</summary>

1,080 rides have a negative fare. After the `DELETE` the table has 21,279,708 rows, but `"rides_month$files"` still
lists the same 992 data files and 21,280,788 rows: the data files did not change. The snapshot list shows an append,
then an overwrite that added 564 delete files, and S3 holds 1,556 files (992 + 564).

A delete file lists which rows of a data file are deleted (L11), and readers skip those rows. The deleted rides are still in the
data files, and the older snapshot still reads them. Steps 4 and 5 take them out of S3.
</details>

### Step 4: compact the table

[`sql/03_compact.sql`](sql/03_compact.sql)

<details>
<summary>Check your predictions</summary>

31 files of 9.6 MB, 21,279,708 rows: one file per day, and the deletes are applied. `OPTIMIZE` read about 420 MB. The
snapshot list shows append, overwrite, then replace (31 added, 992 removed). Our week report: 0.9 s and 9.8 MB after,
against 0.8 s and 13.1 MB before, with the same answer apart from the deleted rides. Compaction removes per-file
work: opening 31 files and reading their footers, not 992.
</details>

### Step 5: remove the old files for good

[`sql/04_expire_old_snapshots.sql`](sql/04_expire_old_snapshots.sql), with the S3 count from Step 3 before and after.

<details>
<summary>Check your predictions</summary>

Before `VACUUM`, S3 holds 1,587 files: 992 old data files, 564 delete files and 31 new ones. The append's snapshot
still reads the 1,080 deleted rides.

`VACUUM` expires only snapshots older than the 60 seconds. In our run the first `VACUUM` expired the append and deleted
no file: the overwrite, only seconds old, still needed the old files. A minute later a second `VACUUM` expired the
overwrite too, and S3 held 31 files. Time travel to the append then fails.

After both steps the deleted rides are gone from S3 and from every snapshot. Delete, then compact, then expire: that
order is what makes a deletion final, and A3's erasure requests need it.
</details>

### Step 6: price the run

In CloudShell:

```
aws glue get-job-runs --job-name rides-month --max-items 1 --query 'JobRuns[0].[ExecutionTime,DPUSeconds]'
```

Glue bills DPU-seconds: DPUs × run time (two G.1X workers are 2 DPUs), at $0.44 per DPU-hour in ca-central-1, per
second with a 1-minute minimum. Price one run, and the same run every night for a year.

<details>
<summary>Check your answer</summary>

Our run: `[189, 379.0]`, so 379 / 3600 × 0.44 = $0.046 a run, about $17 a year of nightly runs. A3 asks the same for
its own jobs and compares it with a small EMR cluster.
</details>

Last question: which line would you change so the job writes fewer files in the first place?

<details>
<summary>One answer</summary>

Drop or lower `repartition(32)`, or change `write.distribution-mode` from `none` so Iceberg groups the rows by day
before writing.
</details>

## 4. Extra exercises

**A second month.** Load April into the same table, then compact again, with
[`sql/05_extra_second_month.sql`](sql/05_extra_second_month.sql). Start the job for April first:

```
aws glue start-job-run --job-name rides-month --arguments '{"--MONTH":"2024-04"}'
```

<details>
<summary>Check your predictions</summary>

Before: March 31 files, April 960. `OPTIMIZE` reads about 390 MB, April only: it rewrites only partitions with small
files, and March was already compacted. After: March 31, April 30. A table that gets a month at a time needs this:
compact the new month after each load.
</details>

**Apply changes by key with `MERGE`, twice**, with [`sql/06_extra_merge.sql`](sql/06_extra_merge.sql). `MERGE`
matches each incoming row to the table by a key: it updates the rows that match and inserts the rest. Rides have no
unique key, so this uses the zone lookup, keyed by `locationid`.

<details>
<summary>Check your predictions</summary>

265 zones before, 266 after the first `MERGE` (two renamed, one added), and still 266 after the second. Tutorial 1's
`INSERT` run twice doubled the rows. `MERGE` run twice leaves the same rows, though it still records a new snapshot.
If two incoming rows matched the same zone, `MERGE` would fail rather than guess which one wins (L11). A3 applies its members' changes this way.
</details>

## 5. Clean up

Run [`sql/99_clean_up.sql`](sql/99_clean_up.sql) in Athena, then in CloudShell:

```
aws glue delete-job --job-name rides-month
```

## Files

| File | What it is |
|---|---|
| [`setup_t2.sh`](setup_t2.sh) | One-time setup: the Glue role's read access to the course lake, the job script in your bucket, the job `rides-month` |
| [`load_rides_month.py`](load_rides_month.py) | The Glue job: reads one month of rides and the zone lookup, writes the Iceberg table `tutorial.rides_month` |
| [`sql/`](sql/) | The SQL for each step, with what to predict in the comments |
