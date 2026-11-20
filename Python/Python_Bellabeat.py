"""Prepare the 11 original Fitbit CSV datasets for analysis/BigQuery.

Usage:
    python clean_fitbit_csv.py --input-dir data/raw --output-dir data/cleaned

Requires Python 3.9+; no third-party packages.

Date output uses DD/MM/YYYY to match the earlier cleaned Fitbit files.
For BigQuery DATE columns, ISO YYYY-MM-DD is generally easier to import;
use --date-format iso for that alternative.

This script does NOT remove zero-step days, outliers, or duplicates. Those
analytical decisions belong to the SQL stage and are documented separately.
"""

import argparse
import csv
from datetime import datetime
from pathlib import Path

# Dataset basename: timestamp/date column to transform.
DATASETS = {
    "dailyActivity_merged": "ActivityDate",
    "hourlyCalories_merged": "ActivityHour",
    "hourlyIntensities_merged": "ActivityHour",
    "hourlySteps_merged": "ActivityHour",
    "heartrate_seconds_merged": "Time",
    "minuteCaloriesNarrow_merged": "ActivityMinute",
    "minuteIntensitiesNarrow_merged": "ActivityMinute",
    "minuteMETsNarrow_merged": "ActivityMinute",
    "minuteSleep_merged": "date",
    "minuteStepsNarrow_merged": "ActivityMinute",
    "weightLogInfo_merged": "Date",
}

INPUT_FORMATS = ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y")


def parse_timestamp(value: str) -> datetime:
    for fmt in INPUT_FORMATS:
        try:
            return datetime.strptime(value.strip(), fmt)
        except ValueError:
            pass
    raise ValueError(f"Unsupported date/time: {value!r}")


def clean_file(source: Path, destination: Path, date_column: str, date_format: str) -> int:
    destination.parent.mkdir(parents=True, exist_ok=True)
    date_output = "%Y-%m-%d" if date_format == "iso" else "%d/%m/%Y"
    count = 0
    with source.open("r", newline="", encoding="utf-8-sig") as infile, \
         destination.open("w", newline="", encoding="utf-8") as outfile:
        reader = csv.DictReader(infile)
        if not reader.fieldnames or date_column not in reader.fieldnames:
            raise ValueError(f"Missing {date_column!r} in {source.name}")

        # Date-only activity records retain their original column name.
        if date_column == "ActivityDate":
            fields = list(reader.fieldnames)
        else:
            fields = []
            for name in reader.fieldnames:
                if name == date_column:
                    fields.extend(["Date", "Time"])
                else:
                    fields.append(name)

        writer = csv.DictWriter(outfile, fieldnames=fields)
        writer.writeheader()
        for line_number, row in enumerate(reader, start=2):
            try:
                timestamp = parse_timestamp(row[date_column])
            except ValueError as exc:
                raise ValueError(f"{source.name}, CSV line {line_number}: {exc}") from exc

            if date_column == "ActivityDate":
                row[date_column] = timestamp.strftime(date_output)
            else:
                # Rebuild row so Date and Time appear where the source
                # timestamp column originally appeared.
                cleaned = {}
                for name in reader.fieldnames:
                    if name == date_column:
                        cleaned["Date"] = timestamp.strftime(date_output)
                        cleaned["Time"] = timestamp.strftime("%H:%M:%S")
                    else:
                        cleaned[name] = row[name]
                row = cleaned
            writer.writerow(row)
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("data/raw"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/cleaned"))
    parser.add_argument("--date-format", choices=["dmy", "iso"], default="dmy")
    args = parser.parse_args()

    for basename, date_column in DATASETS.items():
        matches = sorted(args.input_dir.glob(f"{basename}*.csv"))
        if len(matches) != 1:
            raise FileNotFoundError(
                f"Expected exactly one CSV matching {basename}*.csv in "
                f"{args.input_dir}; found {len(matches)}"
            )
        destination = args.output_dir / f"{basename}_cleaned.csv"
        records = clean_file(matches[0], destination, date_column, args.date_format)
        print(f"{matches[0].name} -> {destination.name}: {records:,} records")


if __name__ == "__main__":
    main()
