# B3T2: build and maintain a table (Glue and Athena)

This tutorial follows L11 and opens Assignment 3. Tutorial 1 gave you a first try at using and changing a lakehouse
table in Athena. Here you try the other two kinds of work A3 asks for, on the same New York rides:

- **Build.** A ready Glue job in Spark loads one month of rides into an Iceberg table in your account. It joins each
  pickup to its borough from the zone lookup. You read the script and predict what it will produce.
- **Maintain.** The table starts with many small files. You delete some rows, compact the table with `OPTIMIZE`,
  expire old snapshots with `VACUUM`, and count the files in S3 after each step.

A3 asks for the same moves on the grocer data, with less given to you. The main path costs about 4 cents, almost all of it for
one Glue run, and Athena adds under a cent. The extra exercises add about 3 cents, almost all of it for the April run.

All course tutorials are listed on the [Tutorials page](https://cpsc436c-2026w1.github.io/lecture-reviews/tutorials.html).

## 1. Before you start

We will reuse the setup from the Glue tutorial and the Athena tutorial, and add some new settings in the next step. 
You probably **won't** need to rerun old setup scripts, but the check script below will tell you if you do. 

To check both, and later this tutorial's own setup, open **CloudShell** with the `>_` icon in the top bar and paste
this line. 

Each line says ✔ or ✗. For each ✗ it will show you how to fix it.
**Before you do the next step (2), the last three checks show ✗ (the Glue role's access to the course lake, the job script and
the job `rides-month`), this is okay. We will create them in a second**.

```
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/check_t2.sh && bash check_t2.sh
```

As a reminder, the Glue tutorial's setup script
[`setup_glue.sh`](https://github.com/cpsc436c-2026w1/l7-spark-glue#1-set-up-your-account-once) created your bucket
`436c-glue-<your account number>` and the Glue role `436c-glue-notebook`. The Athena tutorial's setup script
[`setup_athena.sh`](https://github.com/cpsc436c-2026w1/b3-t1-athena-rides#1-set-up-your-account-once) set the Athena
result location, the Data scanned limit and the `course` data source. Both work in Region **Canada (Central)**.
It is a good idea to review the setup scripts on your own to learn a bit about IAM and each service's limits and best practices.

## 2. Set up the job (once)

Open **CloudShell** with the `>_` icon in the top bar and paste:

```
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/setup_t2.sh && \
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/load_rides_month.py && \
bash setup_t2.sh
```

The script ends with these lines:

```
job     rides-month created

Start it:  aws glue start-job-run --job-name rides-month
Watch it:  Glue console > ETL jobs > rides-month > Runs (about 2.5 minutes)
```

Now run the check from section 1 again. Every line should show ✔, and the last one says the job has not run yet.
If a line still shows ✗, run the fix it prints, then the check again, before you start Step 1.

```
curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/check_t2.sh && bash check_t2.sh
```

**Where the job comes from.** A Glue job is a script in S3, plus settings that say how to run it. The three lines
above did both steps for you:

1. `curl` downloaded the job script, [`load_rides_month.py`](load_rides_month.py), from this repository into
   CloudShell.
2. `setup_t2.sh` copied the script to your bucket, at
   `s3://436c-glue-<your account number>/tutorial2/load_rides_month.py`.
3. `setup_t2.sh` then created the job `rides-month`. The job points at that S3 file and runs it as your Glue role
   `436c-glue-notebook`, on Glue 5.0 with two G.1X workers. Its default arguments set the month
   (`--MONTH 2024-03`) and the database (`--DATABASE tutorial`). The script also lets the role read the course lake,
   which the job reads its rides from.

This is the usual pathway for any Glue job: write the script, put it in S3, then create a job that names the script,
a role and the workers. In the console, **Glue**, **ETL jobs**, `rides-month` shows the job's settings on **Job
details** and the script itself on **Script**. A G.1X worker counts as 1 DPU (Data Processing Unit), the unit Glue
bills compute in.

You can safely rerun it, and a rerun resets the job `rides-month` to its original settings. If it stops with a line
starting `STOP:`, do what that line says. It either names a setup to run first, or asks you to send the error and
your account number to your TA. Whenever a step fails, run the check from section 1 again first.

## 3. Steps

Step 1 starts the Glue job from CloudShell. From Step 2 on, you check and change the table with SQL in the Athena query
editor, with **Data source** `AwsDataCatalog`, one statement at a time, and you count its files in S3 from CloudShell.
Each step's SQL is in [`sql/`](sql/), and its comments say what to predict before you run a statement. Write each
prediction down, then open the step's box after you have run it.

### Step 1: start the job, then read it while it runs

In the [Block 2 Glue tutorial](https://github.com/cpsc436c-2026w1/l7-spark-glue), we used Glue notebooks for
interactive queries. Repeated work, such as an ETL load like this one, is better run as a Glue job. A job is
reproducible: every run uses the same script and settings. You are billed only for the run itself, and you don't need
to worry about starting and stopping a notebook session. A job can also run on a schedule with EventBridge Scheduler,
for example every night.

Start the job once, with this command in CloudShell. It prints a job-run id.

```
aws glue start-job-run --job-name rides-month
```

Watch the run in the console: **Glue**, **ETL jobs**, `rides-month`, **Runs**. Don't press **Run** there, because that
starts a second run, which loads March again and doubles the table. The run reaches **Succeeded** after about 2.5
minutes. If it fails, the **Runs** page shows the error. While it runs, open
[`load_rides_month.py`](load_rides_month.py) and write down your answers to these questions.

1. Which line decides how the table is partitioned? Will March have roughly one partition, about 30 partitions, or
   hundreds of partitions?
2. Do you expect roughly one data file per day, dozens per day, or hundreds per day?
3. What would happen if the job ran a second time?

<details>
<summary>Check your predictions (open after the run)</summary>

1. The call `.partitionedBy(F.days("pickup_datetime"))` partitions by pickup day, so March has one partition for
   each of its 31 days.
2. The call `repartition(32)` makes 32 Spark partitions, with one task for each. The table property
   `write.distribution-mode = none` lets each task write its rows for every day it holds, so a day can get up to 32
   files, one from each task. In Step 2 you count the files and divide by 31.
3. The job appends the month again, so the row count doubles. The script does not check which months it has already
   loaded. This is Tutorial 1's load-twice problem in a Glue job.
</details>

### Step 2: check what the job built

Run the statements of [`sql/01_check_the_table.sql`](sql/01_check_the_table.sql) in the Athena query editor, one at
a time. The first statement counts the table's files and rows. `DESCRIBE` then lists the table's columns, and a
column's place in that list, counting from 1, is its field id. A query on `"rides_month$files"` adds up
`column_sizes`, the size of each column in each file, for the files of 10 to 16 March. The last statement is the week
report, which shows the number of trips and the average fare for each pickup borough in that week. Use the sizes to
predict the week report's Data scanned before you run it. After it runs, write down its run time and Data scanned,
because you compare them in Step 4.

<details>
<summary>Check your predictions</summary>

Divided by the 31 days of March, the file count is close to the 32 tasks of `repartition(32)`, one file from each
task for each day. The job built a rides table that
includes pickup borough, which it joined from the zone lookup.

The week report's Data scanned matches `fare_and_borough_mb` and is well below `three_columns_mb`. Athena did not read
`pickup_datetime`, because the week's range lines up with whole-day partitions, so the partitions answer the filter. A3's task 1.1 uses the same move to
predict Data scanned from `column_sizes`.
</details>

### Step 3: delete some rows

Run [`sql/02_delete_some_rows.sql`](sql/02_delete_some_rows.sql) in the Athena query editor, one statement at a time.
Write down the prediction its comments ask for before you run the `DELETE`. Then count the table's files in S3 with
this command in CloudShell, and compare the number with the file count from `"rides_month$files"`. The command looks
up your account number itself and prints one number.

```
aws s3 ls s3://436c-glue-$(aws sts get-caller-identity --query Account --output text)/tutorial2/warehouse/tutorial.db/rides_month/data/ --recursive | wc -l
```

<details>
<summary>Check your predictions</summary>

After the `DELETE`, the visible row count is lower by the number of negative fares you noted. `"rides_month$files"`
lists the same data files as before, and its `stored_records` total is unchanged, because the data files did not
change. The snapshot list shows an append followed by an overwrite, and the overwrite added delete files. The S3 count
equals the `$files` count plus the overwrite's `delete_files`, because Athena's `$files` does not list delete files.

A delete file lists which rows of a data file are deleted (L11), and readers skip those rows. The deleted rides are
still in the data files, and the older snapshot still reads them. Step 4 writes replacement data files without the
deleted rides. Step 5 removes the obsolete data and delete files from S3 once no kept snapshot needs them.
</details>

### Step 4: compact the table

Run [`sql/03_compact.sql`](sql/03_compact.sql) in the Athena query editor, one statement at a time. Then run the week
report from Step 2 again, and compare its run time and Data scanned with the numbers you wrote down in Step 2. Count
the files in S3 again with the command from Step 3.

<details>
<summary>Check your predictions</summary>

After `OPTIMIZE`, the table has one file for each day, and the visible row count is the same as after the `DELETE`,
because the rewrite applies the deletes. The snapshot list shows append, overwrite, then replace, and the replace
added one file per day and removed all the old data files. The week report scans less data than in Step 2 and
returns the same answer apart from the deleted rides. A query on the week now opens one file per day instead of
dozens. The S3 count rose by the number of new files, because the old files stay until Step 5.
</details>

### Step 5: remove the old files for good

Run [`sql/04_expire_old_snapshots.sql`](sql/04_expire_old_snapshots.sql) in the Athena query editor, one statement at
a time and in order. First count the files in S3 with the CloudShell command from Step 3 and write the number down.
The file asks you to replace `<snapshot_id of the append>` with a number from its first query, in two places. After
the last `VACUUM`, count the files in S3 again. If the snapshot list still shows more than one snapshot, wait a minute,
run `VACUUM` again, and count the files once more.

<details>
<summary>Check your predictions</summary>

Before `VACUUM`, S3 holds the old data files, the delete files and the replacement files together, so its count is the
one from Step 4. The append's snapshot still reads the deleted rides.

`VACUUM` expires snapshots older than 60 seconds and always keeps the newest one. At a normal pace the `DELETE` is
more than a minute old by then, so one `VACUUM` expires both the append and the overwrite. S3 then holds only the
replacement files, one per day, and time travel to the append fails. A `VACUUM` run within about a minute of the
`DELETE` keeps the overwrite, which still needs the old files, so no file is deleted until a second `VACUUM`.

After this step the deleted rides are gone from S3 and from every snapshot. The order is delete, then compact, then
expire. That order makes a deletion final, and A3's erasure requests need it.
</details>

### Step 6: price the run

Run this command in CloudShell:

```
aws glue get-job-runs --job-name rides-month --max-items 1 --query 'JobRuns[0].[ExecutionTime,DPUSeconds]'
```

The command prints two numbers, the run time in seconds and the DPU-seconds, which are the DPUs times the run time.
Your job's two G.1X workers are 2 DPUs. Glue charges $0.44 per DPU-hour in Canada (Central), billed per second with a
1-minute minimum. Price one run, and then the same run every night for a year.

<details>
<summary>Check your answer</summary>

The run time varies. Across five of our runs it was 138 to 170 seconds, which is 276 to 341 DPU-seconds, and about
150 seconds and 300 DPU-seconds on average. So one run costs about 300 / 3600 × $0.44 = $0.037, between $0.034 and
$0.042, and nightly runs for a year cost about 365 × $0.037, roughly $13. Your own numbers will land near these. A3 asks the same for its
own jobs and compares them with a small EMR cluster.
</details>

Finally, open [`load_rides_month.py`](load_rides_month.py) again and decide which line you would change so that the job
writes fewer files for each day.

<details>
<summary>One answer</summary>

Lower `repartition(32)`, or change `write.distribution-mode` from `none` so that Iceberg groups rows by day before
writing. The job sets `write.distribution-mode` only when it creates the table. To try a change, edit `load_rides_month.py` in
CloudShell and run `bash setup_t2.sh` again, so that the edited script reaches your bucket. Then run
`DROP TABLE tutorial.rides_month;` in Athena and start the job again with the command from Step 1.
</details>

## 4. Extra exercises

If you have time for only one extra exercise, do the second one, because task 3.2 of A3 also applies changes to a
table with a `MERGE`.

**Load a second month.** The job loads April into the same table, and then you compact the table again. Start the
job for April with this command in CloudShell:

```
aws glue start-job-run --job-name rides-month --arguments '{"--MONTH":"2024-04"}'
```

Wait until the run shows **Succeeded**, about 2.5 minutes. Then run
[`sql/05_extra_second_month.sql`](sql/05_extra_second_month.sql) in the Athena query editor, one statement at a time.

<details>
<summary>Check your predictions</summary>

Before compaction, March has one file for each day, and April has dozens of files for each of its 30 days.
`OPTIMIZE` rewrites only April. Athena rewrites a partition only when at least 5 of its data files need rewriting (the
table property `optimize_rewrite_data_file_threshold`, default 5), and each March day now has one file. Its Data
scanned is close to that of the March compaction, because April is about as large as March. Afterwards, April
has one file for each day, like March. A table that gets a month at a time needs the same routine, so compact
the new month after each load.
</details>

**Apply changes by key with `MERGE`, twice.** Run [`sql/06_extra_merge.sql`](sql/06_extra_merge.sql) in the Athena
query editor, one statement at a time, after you replace `<account>` with your account number in its two `location`
lines. `MERGE` matches each incoming row to the table by a key. It updates the rows that match and inserts the rest. Rides have no
unique key, so this uses the zone lookup, keyed by `locationid`.

<details>
<summary>Check your predictions</summary>

The table has one zone more after the first `MERGE` than before it, and the second `MERGE` leaves the count unchanged.
The first `MERGE` renamed two zones and added one. Tutorial 1's `INSERT` run twice doubled the rows. `MERGE` run
twice leaves the same rows, though it still records a new snapshot. If two incoming rows matched the same zone,
`MERGE` would fail rather than guess which one wins (L11).
</details>

**🔬 Explore on your own: rerun the job on Glue 6.0.** This one is optional, and you don't have to run it. Glue 6.0,
released in August 2026, prices a standard job run at $0.308 per DPU-hour in ca-central-1, against $0.44 for Glue
5.0 ([Glue pricing](https://aws.amazon.com/glue/pricing/),
[what changed in Glue 6.0](https://docs.aws.amazon.com/glue/latest/dg/migrating-version-60.html)). To try it, run
these steps in order, after Step 6.

1. In CloudShell, make a Glue 6.0 copy of the job, `rides-month-g6`. The original `rides-month` stays as it is.

   ```
   curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t2-glue-rides/main/rerun_glue6.sh && bash rerun_glue6.sh
   ```

2. Clean up for the rerun. Wait until no run of `rides-month` is still going, then run this in Athena. The new job
   creates the table again.

   ```sql
   DROP TABLE tutorial.rides_month;
   ```

3. In CloudShell, start the copy once, and watch it on its own **Runs** tab (**Glue**, **ETL jobs**,
   `rides-month-g6`).

   ```
   aws glue start-job-run --job-name rides-month-g6
   ```

4. When it shows **Succeeded**, read its run time and DPU-seconds.

   ```
   aws glue get-job-runs --job-name rides-month-g6 --max-items 1 --query 'JobRuns[0].[ExecutionTime,DPUSeconds]'
   ```

Then answer two questions. What happened to the run time, compared with your run in Step 6? How would your price
estimate change if the job loaded 100 times as much data each night?

<details>
<summary>One answer</summary>

In our runs, Glue 6.0 took 128 to 129 s and 257 to 258 DPU-seconds, so one run cost about 258 / 3600 × 0.308 = $0.022, against about
$0.037 on Glue 5.0. One run is too few to say Glue 6.0 is faster. Run times vary by tens of seconds, and the saving
comes from the price per DPU-hour. At 100 times the data, if the work grows in proportion, one run takes about 100
times the DPU-seconds. That is about $2.20 a run on Glue 6.0 against about $3.70 on Glue 5.0, or about $800 against
$1,350 for a year of nightly runs. The 1-minute minimum no longer matters at that size, so the 30% lower rate is
the whole difference. A load that size would also get more workers, which shortens the run but costs about the same
DPU-seconds.
</details>

## 5. Clean up

Run the four statements of [`sql/99_clean_up.sql`](sql/99_clean_up.sql) in Athena, one at a time. The three
`DROP TABLE` statements and `DROP DATABASE` should all succeed. Refresh the `AwsDataCatalog` list, and the `tutorial`
database should be gone. For an Iceberg table, `DROP TABLE` also deletes its data files. If `DROP DATABASE` fails
because the database is not empty, Tutorial 1's tables are still in it. Run Tutorial 1's clean-up, then run
`DROP DATABASE` again.

Then delete the job with this command in CloudShell:

```
aws glue delete-job --job-name rides-month
aws glue delete-job --job-name rides-month-g6   # only if you did the Glue 6.0 exercise
```

It prints `{"JobName": "rides-month"}`. Then check what is left of the tutorial in your bucket with this command in
CloudShell:

```
aws s3 ls s3://436c-glue-$(aws sts get-caller-identity --query Account --output text)/tutorial2/ --recursive
```

The only file left should be the job script, `tutorial2/load_rides_month.py`. Your bucket, the Glue role and its
policy stay, because A3 uses them. The job script left in your bucket adds a small S3 storage charge.

## 6. Recap and reflection

<details>
<summary>What you did, why, and how the same work runs outside this tutorial (open after the tutorial)</summary>

- **You loaded the month with a Glue job, not a notebook.** In the Block 2 Glue tutorial, notebooks were for
  interactive work. A load that repeats is better as a job, because every run uses the same script and settings, you
  pay only for the run, and a scheduler can start it every night. Real pipelines run their loads this way.
- **You checked the table in Athena.** Athena is the table's main consumer, so you checked it from the consumer's
  side. Engines sometimes treat a table slightly differently, and Athena shows what the people who query it get. Its
  Data scanned also shows what each query costs, so you can see whether a change to the load makes later queries
  cheaper or dearer.
- **You predicted Data scanned from the table's own metadata.** `column_sizes` in `"rides_month$files"` gives the
  bytes each column takes in each file. A filter that lines up with the day partitions doesn't even read its date
  column. A3's task 1.1 asks you to make the same prediction before a large query.
- **You counted files in S3 as well as in the table.** The table lists the files of its current snapshot. S3 holds
  every file that some snapshot still needs, and you pay to store all of them.
- **You deleted, compacted and expired, in that order.** `DELETE` only writes delete files, so the rows are hidden
  but still stored. `OPTIMIZE` rewrites the data files without those rows and merges small files into larger ones.
  `VACUUM` then removes snapshots older than the table's age setting, with the files only they needed. In real
  systems this order is what makes an erasure request final, and the age setting comes from a retention policy,
  usually days rather than 60 seconds.
- **You saw why small files cost.** The job wrote 32 small files a day because 32 tasks each wrote some of every
  day. Compaction fixes it after the fact. Fewer tasks, or a write that groups rows by day, fixes it at the source.
- **You priced the work.** A load is priced by its DPU-seconds, and a query by its Data scanned. Multiplying one run
  by a year of nightly runs is how you compare engines. A3's task 2 compares Glue with an EMR cluster this way.

</details>

## Files

| File | What it is |
|---|---|
| [`check_t2.sh`](check_t2.sh) | This script checks your account for the earlier setups and this tutorial's setup, changes nothing, and says what to run for anything missing. |
| [`rerun_glue6.sh`](rerun_glue6.sh) | For the optional Glue 6.0 exercise. This script makes a Glue 6.0 copy of the job, `rides-month-g6`, with the same script, role, workers and arguments. |
| [`setup_t2.sh`](setup_t2.sh) | This script performs the one-time setup. It grants the Glue role read access to the course lake, copies the job script to your bucket, and creates `rides-month`. |
| [`load_rides_month.py`](load_rides_month.py) | This Glue job reads one month of rides and the zone lookup, then writes `tutorial.rides_month`. |
| [`sql/`](sql/) | This directory contains the SQL for each step, with the prediction prompts in the comments. |
