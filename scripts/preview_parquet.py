#!/usr/bin/env python3
"""
Preview script for Parquet files in lf file manager.
Displays schema, row count, and sample data from parquet files.
"""

import os
import sys

import pandas as pd


def format_size(size_bytes):
    """Format file size in human-readable format."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} PB"


def preview_parquet(file_path):
    """Preview a parquet file."""
    try:
        # Get file info
        file_stat = os.stat(file_path)
        file_size = format_size(file_stat.st_size)

        # Read parquet file
        df = pd.read_parquet(file_path)

        # Print header
        print("=" * 80)
        print(f"Parquet File: {os.path.basename(file_path)}")
        print(f"Size: {file_size}")
        print("=" * 80)
        print()

        # Print shape info
        print(f"Shape: {df.shape[0]:,} rows × {df.shape[1]} columns")
        print()

        # Print column info
        print("Columns:")
        print("-" * 80)
        for col in df.columns:
            dtype = str(df[col].dtype)
            null_count = df[col].isna().sum()
            null_pct = (null_count / len(df)) * 100 if len(df) > 0 else 0
            print(
                f"  {col:30s} {dtype:15s} (nulls: {null_count:,} ({null_pct:.1f}%))"
            )
        print()

        # Print sample data
        print("Sample Data (first 10 rows):")
        print("-" * 80)

        # Limit columns if too many
        max_cols = 8
        if len(df.columns) > max_cols:
            display_df = df.iloc[:10, :max_cols]
            print(f"(Showing first {max_cols} of {len(df.columns)} columns)")
        else:
            display_df = df.head(10)

        # Format output nicely
        pd.set_option("display.max_columns", None)
        pd.set_option("display.width", None)
        pd.set_option("display.max_colwidth", 50)

        print(display_df.to_string(index=True))

        if len(df) > 10:
            print(f"\n... and {len(df) - 10:,} more rows")

    except Exception as e:
        print(f"Error reading parquet file: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print("Usage: preview_parquet.py <file_path>", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]

    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(file_path):
        print(f"Error: Not a file: {file_path}", file=sys.stderr)
        sys.exit(1)

    preview_parquet(file_path)


if __name__ == "__main__":
    main()
