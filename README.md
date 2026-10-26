# B3T2: build and maintain a table (Glue and Athena)

This tutorial follows L11 and opens Assignment 3. Tutorial 1 gave you a first try at using and changing a lakehouse
table in Athena. Here you try the other two kinds of work A3 asks for, on the same New York rides:

- **Build.** A ready Glue job in Spark loads one month of rides into an Iceberg table in your account. It joins each
  pickup to its borough from the zone lookup. You read the script and predict what it will produce.
- **Maintain.** The table starts with many small files. You delete some rows, compact the table with `OPTIMIZE`,
  expire old snapshots with `VACUUM`, and count the files in S3 after each step.

A3 asks for the same moves on the grocer data, with less given to you. The main path costs about 4 cents. That is one
Glue run of about 300 DPU-seconds at $0.44 per DPU-hour, plus Athena under a cent. The extra exercises add about
3 cents for the April run.

All course tutorials are listed on the [Tutorials page](https://cpsc436c-2026w1.github.io/lecture-reviews/tutorials.html).

## 1. Before you start

You need two earlier setups, both in Region **Canada (Central)**:

- **Tutorial 1's setup** ([b3-t1-athena-rides](https://github.com/cpsc436c-2026w1/b3-t1-athena-rides), section 1):
  the Athena result location, the Data scanned limit and the `course` data source.
- **L7's `setup_glue.sh`** ([l7-spark-glue](https://github.com/cpsc436c-2026w1/l7-spark-glue)): your bucket
  `436c-glue-<your account number>` and the Glue role `436c-glue-notebook`.

To check both, and later this tutorial's own setup, run this in CloudShell. It only reads your account. Each line
says ✔ or ✗, and each ✗ says what to run.

```
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/check_t2.sh && bash check_t2.sh
```

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

You can safely rerun it, and a rerun resets the job `rides-month` to its original settings. If it stops with a line
starting `STOP:`, do what that line says. It either names a setup to run first, or asks you to send the error and
your account number to your TA. Whenever a step fails, run the check from section 1 again first.

## 3. Steps

Run SQL in the Athena query editor with **Data source** `AwsDataCatalog`, one statement at a time. Each step's SQL is
in [`sql/`](sql/), and its comments say what to predict before you run a statement. Write each prediction down, then open
the step's box after you have run it.

### Step 1: start the job, then read it while it runs

Run this command in CloudShell:

```
aws glue start-job-run --job-name rides-month
```

The command prints a job-run id. In the Glue console, open **ETL jobs**, choose `rides-month`, and open **Runs**. The
run should reach **Succeeded** after about 2.5 minutes. During the run, open
[`load_rides_month.py`](load_rides_month.py) and write down your answers to these questions.

1. Which line decides how the table is partitioned? Will March have roughly one partition, about 30 partitions, or
   hundreds of partitions?
2. Do you expect roughly one data file per day, dozens per day, or hundreds per day?
3. What would happen if the job ran a second time?

<details>
<summary>Check your predictions (open after the run)</summary>

1. The call `.partitionedBy(F.days("pickup_datetime"))` partitions by pickup day, so March has about 30 partitions.
   In our run, it had 31.
2. The call `repartition(32)` makes 32 Spark partitions, with one task for each. The table property
   `write.distribution-mode = none` lets each task write its rows for every day it holds, so dozens of files per day
   are plausible. In our run, there were 32 files per day and 992 files averaging about 0.4 MB.
3. The job appends the month again, so the row count roughly doubles. In our run, it rose from 21,280,788 to
   42,561,576 rows. The script does not check which months it has already loaded. This is Tutorial 1's load-twice
   problem in a Glue job.
</details>

### Step 2: check what the job built

[`sql/01_check_the_table.sql`](sql/01_check_the_table.sql)

Run its statements in the Athena query editor, one at a time. The file first counts the table's files and rows. Then `DESCRIBE` gives each column's field id, and a query on
`"rides_month$files"` adds up `column_sizes` for the week's files. Use those sizes to predict the week report's Data
scanned before you run it.

<details>
<summary>Check your predictions</summary>

In our run, the table had 992 files averaging 0.4 MB and 21,280,788 rows. The week report showed trips and average
fare by pickup borough. The job built a rides table that includes pickup borough, which it joined from the zone
lookup. The report took 0.8 seconds and had 13.1 MB of Data scanned.

In our run, the three columns the week report names summed to 35.3 MB in the week's files. Fare and borough alone
summed to 13.1 MB, which equals the report's Data scanned. Athena did not read `pickup_datetime`, because the week's
range lines up with whole-day partitions, so the partitions answer the filter. A3's task 1.1 uses the same move to
predict Data scanned from `column_sizes`.
</details>

### Step 3: delete some rows

Run [`sql/02_delete_some_rows.sql`](sql/02_delete_some_rows.sql). Then count the table's files in S3 with this
command in CloudShell:

```
aws s3 ls s3://436c-glue-<your account number>/tutorial2/warehouse/tutorial.db/rides_month/data/ --recursive | wc -l
```

<details>
<summary>Check your predictions</summary>

In our run, 1,080 rides had a negative fare. After the `DELETE`, the table had 21,279,708 visible rows.
`"rides_month$files"` still listed the same 992 data files and 21,280,788 stored records. The data files did not
change. The snapshot list showed an append followed by an overwrite that added 564 delete files. S3 then held 1,556
files, which was 992 data files plus 564 delete files.

A delete file lists which rows of a data file are deleted (L11), and readers skip those rows. The deleted rides are
still in the data files, and the older snapshot still reads them. Step 4 writes replacement data files without the
deleted rides. Step 5 removes the obsolete data and delete files from S3 once no kept snapshot needs them.
</details>

### Step 4: compact the table

[`sql/03_compact.sql`](sql/03_compact.sql)

Run it in the Athena query editor. Then run the week report from Step 2 again and compare its Data scanned with
what you noted then.

<details>
<summary>Check your predictions</summary>

In our run, compaction produced 31 files averaging 9.6 MB and kept 21,279,708 visible rows. That is one file per day,
with the deletes applied. `OPTIMIZE` had 422 MB of Data scanned. The snapshot list showed append, overwrite, then
replace, and the replace added 31 files and removed 992. The week report then had 9.8 MB of Data scanned, against
13.1 MB before, with the same answer apart from the deleted rides. Compaction removes per-file work, because Athena
opens 31 files and reads their footers instead of 992. S3 held 1,587 files after compaction.
</details>

### Step 5: remove the old files for good

Run [`sql/04_expire_old_snapshots.sql`](sql/04_expire_old_snapshots.sql) in the Athena query editor, one statement at
a time and in order. Count the files in S3 with the CloudShell command from Step 3 before you start, and again after
the final `VACUUM`.

<details>
<summary>Check your predictions</summary>

In our run, S3 held 1,587 files before `VACUUM`. These were 992 old data files, 564 delete files, and 31 replacement
data files. The append's snapshot still read the 1,080 deleted rides.

`VACUUM` expires snapshots older than 60 seconds and always keeps the newest one. At a student's pace the `DELETE` is
more than a minute old by then, so one `VACUUM` expires both the append and the overwrite. In our run, S3 then held
31 files, and time travel to the append failed. A `VACUUM` run within about a minute of the `DELETE` keeps the
overwrite, which still needs the old files, so no file is deleted until a second `VACUUM`. That is what our first,
scripted run saw.

After this step the deleted rides are gone from S3 and from every snapshot. The order is delete, then compact, then
expire. That order makes a deletion final, and A3's erasure requests need it.
</details>

### Step 6: price the run

Run this command in CloudShell:

```
aws glue get-job-runs --job-name rides-month --max-items 1 --query 'JobRuns[0].[ExecutionTime,DPUSeconds]'
```

Glue bills DPU-seconds: DPUs × run time (two G.1X workers are 2 DPUs), at $0.44 per DPU-hour in ca-central-1, per
second with a 1-minute minimum. Price one run, and the same run every night for a year.

<details>
<summary>Check your answer</summary>

Run times vary. Over five of our runs the command printed between `[138, 276.0]` and `[170, 341.0]`, about
`[150, 300]` on average. So one run costs about 300 / 3600 × 0.44 = $0.037, between $0.034 and $0.042, and nightly
runs for a year cost about 365 × $0.037, roughly $13. Your own numbers will land near these. A3 asks the same for its
own jobs and compares them with a small EMR cluster.
</details>

Finally, decide which line you would change so that the job writes fewer files in the first place.

<details>
<summary>One answer</summary>

Lower `repartition(32)`, or change `write.distribution-mode` from `none` so that Iceberg groups rows by day before
writing. The job sets `write.distribution-mode` only when it creates the table. To try the change, drop
`tutorial.rides_month` before you rerun the changed job.
</details>

## 4. Extra exercises

A3's task 3.2 applies members' changes with this `MERGE`, so the second exercise is the one to do if you do one.

**Load a second month.** Load April into the same table, then compact again, with
[`sql/05_extra_second_month.sql`](sql/05_extra_second_month.sql). Start the job for April first with this command in
CloudShell:

```
aws glue start-job-run --job-name rides-month --arguments '{"--MONTH":"2024-04"}'
```

Wait until the run shows **Succeeded**, about 2.5 minutes, before you run the SQL.

<details>
<summary>Check your predictions</summary>

In our run, March had 31 files and April had 960 files before compaction. `OPTIMIZE` had 394 MB of Data scanned and
rewrote only April, because it rewrites only partitions with small files and March was already compacted. Afterwards,
March still had 31 files and April had 30. A table that gets a month at a time needs the same routine, so compact
the new month after each load.
</details>

**Apply changes by key with `MERGE`, twice**, with [`sql/06_extra_merge.sql`](sql/06_extra_merge.sql). `MERGE`
matches each incoming row to the table by a key. It updates the rows that match and inserts the rest. Rides have no
unique key, so this uses the zone lookup, keyed by `locationid`.

<details>
<summary>Check your predictions</summary>

In our run, the table had 265 zones before the first `MERGE`, 266 after the first `MERGE`, and 266 after the second
`MERGE`. The first one renamed two zones and added one. Tutorial 1's `INSERT` run twice doubled the rows. `MERGE` run
twice leaves the same rows, though it still records a new snapshot. If two incoming rows matched the same zone,
`MERGE` would fail rather than guess which one wins (L11).
</details>

## 5. Clean up

Run the four statements of [`sql/99_clean_up.sql`](sql/99_clean_up.sql) in Athena, one at a time. The three
`DROP TABLE` statements and `DROP DATABASE` should all succeed. Refresh the `AwsDataCatalog` list, and the `tutorial`
database should be gone. For an Iceberg table, `DROP TABLE` also deletes its data files. If `DROP DATABASE` fails
because the database is not empty, tutorial 1's tables are still in it. Run tutorial 1's clean-up, then run
`DROP DATABASE` again.

Then delete the job with this command in CloudShell:

```
aws glue delete-job --job-name rides-month
```

It prints `{"JobName": "rides-month"}`. To check what is left of the tutorial in your bucket, run this command:

```
aws s3 ls s3://436c-glue-<your account number>/tutorial2/ --recursive
```

The only file left should be the job script, `tutorial2/load_rides_month.py`. Your bucket, the Glue role and its
policy stay, and they cost nothing.

## Files

| File | What it is |
|---|---|
| [`check_t2.sh`](check_t2.sh) | This script checks your account for the earlier setups and this tutorial's setup, changes nothing, and says what to run for anything missing. |
| [`setup_t2.sh`](setup_t2.sh) | This script performs the one-time setup. It grants the Glue role read access to the course lake, copies the job script to your bucket, and creates `rides-month`. |
| [`load_rides_month.py`](load_rides_month.py) | This Glue job reads one month of rides and the zone lookup, then writes `tutorial.rides_month`. |
| [`sql/`](sql/) | This directory contains the SQL for each step, with the prediction prompts in the comments. |
