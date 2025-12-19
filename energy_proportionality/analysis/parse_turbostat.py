#!/usr/bin/env python3
"""
Turbostat Log Parser
Extracts CPU power and C-state data from turbostat output
"""

import os
import sys
import re
import csv
import argparse
from pathlib import Path
from typing import List, Dict, Optional
from dataclasses import dataclass
import statistics


@dataclass
class TurbostatSample:
    """Single turbostat measurement sample"""
    timestamp: Optional[str]
    cpu: int
    avg_mhz: float
    busy_percent: float
    bzy_mhz: float
    pkg_watt: Optional[float]
    core_watt: Optional[float]
    c1_percent: float
    c6_percent: float
    c7_percent: float


def parse_turbostat_log(filepath: str) -> List[TurbostatSample]:
    """
    Parse turbostat log file into structured samples

    Args:
        filepath: Path to turbostat log file

    Returns:
        List of TurbostatSample objects
    """
    samples = []

    with open(filepath, 'r') as f:
        content = f.read()

    # Split into sections (each starting with header)
    sections = re.split(r'\n(?=\s*Core\s+CPU)', content)

    for section in sections:
        lines = section.strip().split('\n')

        # Find header line
        header_idx = None
        for i, line in enumerate(lines):
            if 'Core' in line and 'CPU' in line:
                header_idx = i
                break

        if header_idx is None:
            continue

        # Parse header to get column positions
        header = lines[header_idx]
        columns = header.split()

        # Find column indices
        col_map = {}
        for i, col in enumerate(columns):
            col_map[col.lower()] = i

        # Parse data lines
        for line in lines[header_idx + 1:]:
            if not line.strip() or line.startswith('-'):
                continue

            parts = line.split()
            if len(parts) < len(columns):
                continue

            try:
                # Handle different turbostat output formats
                cpu_idx = col_map.get('cpu', 1)
                cpu = int(parts[cpu_idx]) if parts[cpu_idx] != '-' else -1

                if cpu == -1:  # Skip package-level entries for now
                    continue

                sample = TurbostatSample(
                    timestamp=None,
                    cpu=cpu,
                    avg_mhz=float(parts[col_map.get('avg_mhz', 2)]) if 'avg_mhz' in col_map else 0,
                    busy_percent=float(parts[col_map.get('busy%', 3)]) if 'busy%' in col_map else 0,
                    bzy_mhz=float(parts[col_map.get('bzy_mhz', 4)]) if 'bzy_mhz' in col_map else 0,
                    pkg_watt=float(parts[col_map.get('pkgwatt', -1)]) if 'pkgwatt' in col_map else None,
                    core_watt=float(parts[col_map.get('corewatt', -1)]) if 'corewatt' in col_map else None,
                    c1_percent=float(parts[col_map.get('c1%', -1)]) if 'c1%' in col_map else 0,
                    c6_percent=float(parts[col_map.get('c6%', -1)]) if 'c6%' in col_map else 0,
                    c7_percent=float(parts[col_map.get('c7%', -1)]) if 'c7%' in col_map else 0,
                )
                samples.append(sample)

            except (ValueError, IndexError) as e:
                continue

    return samples


def analyze_samples(samples: List[TurbostatSample], cpu_filter: Optional[List[int]] = None) -> Dict:
    """
    Analyze turbostat samples and compute statistics

    Args:
        samples: List of TurbostatSample objects
        cpu_filter: Optional list of CPUs to include

    Returns:
        Dictionary with analysis results
    """
    if cpu_filter:
        samples = [s for s in samples if s.cpu in cpu_filter]

    if not samples:
        return {'error': 'No samples matching filter'}

    # Group by CPU
    by_cpu = {}
    for s in samples:
        if s.cpu not in by_cpu:
            by_cpu[s.cpu] = []
        by_cpu[s.cpu].append(s)

    results = {
        'total_samples': len(samples),
        'cpus': list(by_cpu.keys()),
        'per_cpu': {},
        'aggregate': {}
    }

    # Per-CPU statistics
    for cpu, cpu_samples in by_cpu.items():
        c6_values = [s.c6_percent for s in cpu_samples]
        busy_values = [s.busy_percent for s in cpu_samples]
        freq_values = [s.avg_mhz for s in cpu_samples if s.avg_mhz > 0]

        results['per_cpu'][cpu] = {
            'samples': len(cpu_samples),
            'c6_avg': statistics.mean(c6_values),
            'c6_max': max(c6_values),
            'c6_min': min(c6_values),
            'busy_avg': statistics.mean(busy_values),
            'freq_avg': statistics.mean(freq_values) if freq_values else 0,
        }

    # Aggregate statistics
    all_c6 = [s.c6_percent for s in samples]
    all_busy = [s.busy_percent for s in samples]
    all_pkg_watt = [s.pkg_watt for s in samples if s.pkg_watt is not None]

    results['aggregate'] = {
        'c6_avg': statistics.mean(all_c6),
        'c6_std': statistics.stdev(all_c6) if len(all_c6) > 1 else 0,
        'busy_avg': statistics.mean(all_busy),
        'pkg_watt_avg': statistics.mean(all_pkg_watt) if all_pkg_watt else None,
    }

    return results


def export_to_csv(samples: List[TurbostatSample], output_file: str):
    """Export samples to CSV file"""
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            'cpu', 'avg_mhz', 'busy_percent', 'bzy_mhz',
            'c1_percent', 'c6_percent', 'c7_percent',
            'pkg_watt', 'core_watt'
        ])

        for s in samples:
            writer.writerow([
                s.cpu, s.avg_mhz, s.busy_percent, s.bzy_mhz,
                s.c1_percent, s.c6_percent, s.c7_percent,
                s.pkg_watt or '', s.core_watt or ''
            ])

    print(f"Exported {len(samples)} samples to {output_file}")


def print_analysis(results: Dict, title: str = "Turbostat Analysis"):
    """Print formatted analysis results"""
    print("\n" + "=" * 50)
    print(f"  {title}")
    print("=" * 50)

    if 'error' in results:
        print(f"\nError: {results['error']}")
        return

    print(f"\nTotal Samples: {results['total_samples']}")
    print(f"CPUs Analyzed: {results['cpus']}")

    print("\n" + "-" * 50)
    print("  Per-CPU Statistics")
    print("-" * 50)

    for cpu in sorted(results['per_cpu'].keys()):
        stats = results['per_cpu'][cpu]
        print(f"\n  CPU {cpu}:")
        print(f"    Samples: {stats['samples']}")
        print(f"    C6 Residency: {stats['c6_avg']:.2f}% (min: {stats['c6_min']:.2f}%, max: {stats['c6_max']:.2f}%)")
        print(f"    Busy: {stats['busy_avg']:.2f}%")
        print(f"    Avg Frequency: {stats['freq_avg']:.0f} MHz")

    print("\n" + "-" * 50)
    print("  Aggregate Statistics")
    print("-" * 50)

    agg = results['aggregate']
    print(f"\n  Average C6 Residency: {agg['c6_avg']:.2f}% (+/- {agg['c6_std']:.2f}%)")
    print(f"  Average Busy: {agg['busy_avg']:.2f}%")

    if agg['pkg_watt_avg'] is not None:
        print(f"  Average Package Power: {agg['pkg_watt_avg']:.2f} W")

    print("\n" + "=" * 50)


def main():
    parser = argparse.ArgumentParser(
        description='Parse and analyze turbostat log files'
    )
    parser.add_argument(
        'logfile',
        help='Path to turbostat log file'
    )
    parser.add_argument(
        '--cpus', '-c',
        help='Comma-separated list of CPUs to analyze (e.g., 0,2,4)'
    )
    parser.add_argument(
        '--export', '-e',
        help='Export parsed data to CSV file'
    )

    args = parser.parse_args()

    if not os.path.exists(args.logfile):
        print(f"Error: File not found: {args.logfile}")
        sys.exit(1)

    # Parse log file
    samples = parse_turbostat_log(args.logfile)

    if not samples:
        print("Error: No valid samples found in log file")
        sys.exit(1)

    print(f"Parsed {len(samples)} samples from {args.logfile}")

    # Apply CPU filter
    cpu_filter = None
    if args.cpus:
        cpu_filter = [int(c) for c in args.cpus.split(',')]

    # Analyze
    results = analyze_samples(samples, cpu_filter)
    print_analysis(results)

    # Export if requested
    if args.export:
        filtered_samples = samples
        if cpu_filter:
            filtered_samples = [s for s in samples if s.cpu in cpu_filter]
        export_to_csv(filtered_samples, args.export)


if __name__ == '__main__':
    main()
