#!/usr/bin/env python3
"""
Script to rename GDS VFD entries in benchmark CSV to distinguish between
gds-native and gds-compat modes based on execution order.

The script assumes:
- First half of GDS entries are gds-native (using disable_compat.json)
- Second half of GDS entries are gds-compat (using force_compat.json)
"""

import csv
import sys
from pathlib import Path


def rename_gds_vfd(input_file, output_file=None):
    """
    Rename GDS VFD entries to gds-native and gds-compat.
    
    Args:
        input_file: Path to input CSV file
        output_file: Path to output CSV file (default: input_file with _renamed suffix)
    """
    input_path = Path(input_file)
    
    if output_file is None:
        output_file = input_path.parent / f"{input_path.stem}_renamed{input_path.suffix}"
    
    # Read all rows
    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    
    # Find all GDS entries
    gds_indices = [i for i, row in enumerate(rows) if row['VFD'] == 'gds']
    
    if not gds_indices:
        print("No GDS entries found in the CSV file.")
        return
    
    total_gds = len(gds_indices)
    midpoint = total_gds // 2
    
    print(f"Found {total_gds} GDS entries")
    print(f"Renaming first {midpoint} to 'gds-native'")
    print(f"Renaming remaining {total_gds - midpoint} to 'gds-compat'")
    
    # Rename GDS entries
    for i, idx in enumerate(gds_indices):
        if i < midpoint:
            rows[idx]['VFD'] = 'gds-native'
        else:
            rows[idx]['VFD'] = 'gds-compat'
    
    # Write output
    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    
    print(f"\nOutput written to: {output_file}")
    
    # Print summary
    vfd_counts = {}
    for row in rows:
        vfd = row['VFD']
        vfd_counts[vfd] = vfd_counts.get(vfd, 0) + 1
    
    print("\nVFD distribution in output:")
    for vfd, count in sorted(vfd_counts.items()):
        print(f"  {vfd}: {count} entries")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python rename_gds_vfd.py <input_csv> [output_csv]")
        print("\nExample:")
        print("  python rename_gds_vfd.py input.csv")
        print("  python rename_gds_vfd.py input.csv output.csv")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    rename_gds_vfd(input_file, output_file)