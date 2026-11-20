-- 1. Count participants and observations
-- Original Fitbit dataset
SELECT
  COUNT(*) AS total_records,
  COUNT(DISTINCT Id) AS total_participants
FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`;

-- Norwegian Fitbit participants only
SELECT
  COUNT(*) AS total_records,
  COUNT(DISTINCT ID) AS total_participants
FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
WHERE LOWER(TRIM(Provider)) = 'fitbit';

-- 2. Calculate overall daily step statistics
-- Original Fitbit
SELECT
  COUNT(*) AS recorded_days,
  ROUND(AVG(TotalSteps), 1) AS average_daily_steps,
  MIN(TotalSteps) AS minimum_steps,
  MAX(TotalSteps) AS maximum_steps,
  ROUND(
    100 * COUNTIF(TotalSteps > 10000) / COUNT(*),
    1
  ) AS percentage_days_above_10000
FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`;

-- Norwegian Fitbit
SELECT
  COUNT(*) AS recorded_days,
  ROUND(AVG(Steps), 1) AS average_daily_steps,
  MIN(Steps) AS minimum_steps,
  MAX(Steps) AS maximum_steps
FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
WHERE LOWER(TRIM(Provider)) = 'fitbit';

-- 3. Calculate average steps per participant
WITH combined AS (
  SELECT
    'Original Fitbit' AS study,
    CAST(Id AS STRING) AS user_id,
    TotalSteps AS steps
  FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`

  UNION ALL

  SELECT
    'Norwegian Fitbit' AS study,
    CAST(ID AS STRING) AS user_id,
    Steps AS steps
  FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
  WHERE LOWER(TRIM(Provider)) = 'fitbit'
),
participant_averages AS (
  SELECT
    study,
    user_id,
    AVG(steps) AS average_steps
  FROM combined
  GROUP BY study, user_id
)
SELECT
  study,
  COUNT(*) AS participants,
  ROUND(AVG(average_steps), 1) AS mean_participant_steps,
  ROUND(MIN(average_steps), 1) AS lowest_participant_average,
  ROUND(MAX(average_steps), 1) AS highest_participant_average
FROM participant_averages
GROUP BY study;

-- 4. Check recording coverage after filtering
WITH combined AS (
  SELECT
    'Original Fitbit' AS study,
    CAST(Id AS STRING) AS user_id,
    TotalSteps AS steps
  FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`

  UNION ALL

  SELECT
    'Norwegian Fitbit' AS study,
    CAST(ID AS STRING) AS user_id,
    Steps AS steps
  FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
  WHERE LOWER(TRIM(Provider)) = 'fitbit'
),
valid_days AS (
  SELECT
    study,
    user_id,
    COUNT(*) AS valid_recorded_days
  FROM combined
  WHERE steps BETWEEN 1 AND 100000
  GROUP BY study, user_id
)
SELECT
  study,
  COUNT(*) AS participants,
  MIN(valid_recorded_days) AS minimum_days,
  ROUND(AVG(valid_recorded_days), 1) AS average_days,
  MAX(valid_recorded_days) AS maximum_days,
  COUNTIF(valid_recorded_days < 7) AS participants_below_7_days
FROM valid_days
GROUP BY study;

-- 5. Check for duplicate participant-date records
WITH combined AS (
  SELECT
    'Original Fitbit' AS study,
    CAST(Id AS STRING) AS user_id,
    ActivityDate AS activity_date,
    TotalSteps AS steps
  FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`

  UNION ALL

  SELECT
    'Norwegian Fitbit' AS study,
    CAST(ID AS STRING) AS user_id,
    Date AS activity_date,
    Steps AS steps
  FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
  WHERE LOWER(TRIM(Provider)) = 'fitbit'
)
SELECT
  study,
  user_id,
  activity_date,
  COUNT(*) AS duplicate_count,
  COUNT(DISTINCT steps) AS distinct_step_values
FROM combined
GROUP BY study, user_id, activity_date
HAVING COUNT(*) > 1
ORDER BY study, user_id, activity_date;

-- 6. Final participant activity classification
WITH combined AS (
  SELECT DISTINCT
    'Original Fitbit' AS study,
    CAST(Id AS STRING) AS user_id,
    ActivityDate AS activity_date,
    TotalSteps AS steps
  FROM `deft-condition-312117.casestudy2.Daily_Activity_cleaned`

  UNION ALL

  SELECT DISTINCT
    'Norwegian Fitbit' AS study,
    CAST(ID AS STRING) AS user_id,
    Date AS activity_date,
    Steps AS steps
  FROM `deft-condition-312117.casestudy2.Norwegian_2019_2020`
  WHERE LOWER(TRIM(Provider)) = 'fitbit'
),

valid_activity AS (
  SELECT *
  FROM combined
  WHERE steps BETWEEN 1 AND 100000
),

participant_averages AS (
  SELECT
    study,
    user_id,
    COUNT(*) AS valid_days,
    AVG(steps) AS average_daily_steps
  FROM valid_activity
  GROUP BY study, user_id
  HAVING COUNT(*) >= 7
),

activity_groups AS (
  SELECT
    study,
    user_id,
    average_daily_steps,
    CASE
      WHEN average_daily_steps < 5000 THEN 'Below 5,000'
      WHEN average_daily_steps < 7500 THEN '5,000–7,499'
      WHEN average_daily_steps < 10000 THEN '7,500–9,999'
      ELSE '10,000+'
    END AS activity_category
  FROM participant_averages
)

SELECT
  study,
  activity_category,
  COUNT(*) AS participants,
  ROUND(
    100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY study),
    1
  ) AS percentage
FROM activity_groups
GROUP BY study, activity_category
ORDER BY
  study,
  CASE activity_category
    WHEN 'Below 5,000' THEN 1
    WHEN '5,000–7,499' THEN 2
    WHEN '7,500–9,999' THEN 3
    ELSE 4
  END;
Notes
The final query excludes zero-step days and observations above 100,000 steps, deduplicates matching step observations, and requires at least seven valid records per participant. Zero-step sensitivity analysis was not completed.

