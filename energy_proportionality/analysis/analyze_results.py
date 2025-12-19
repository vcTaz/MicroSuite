#!/usr/bin/env python3
"""
Energy Proportionality Experiment Analysis
Analyzes checkpoint/restore latency and C6 state residency data
"""

import os
import sys
import csv
import glob
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import List, Dict, Optional
import statistics

@dataclass
class ExperimentRun:
    """Data from a single experiment run"""
    run_id: int
    checkpoint_ms: float
    restore_ms: float
    idle_duration_s: float
    c6_residency_percent: float

@dataclass
class ExperimentResults:
    """Aggregated experiment results"""
    runs: List[ExperimentRun]
    baseline_c6: Optional[float] = None

    @property
    def avg_checkpoint_ms(self) -> float:
        valid = [r.checkpoint_ms for r in self.runs if r.checkpoint_ms > 0]
        return statistics.mean(valid) if valid else 0

    @property
    def avg_restore_ms(self) -> float:
        valid = [r.restore_ms for r in self.runs if r.restore_ms > 0]
        return statistics.mean(valid) if valid else 0

    @property
    def avg_c6_residency(self) -> float:
        return statistics.mean([r.c6_residency_percent for r in self.runs])

    @property
    def total_overhead_ms(self) -> float:
        return self.avg_checkpoint_ms + self.avg_restore_ms


def load_results(results_dir: str) -> ExperimentResults:
    """Load experiment results from CSV file"""
    results_file = os.path.join(results_dir, "results.csv")

    if not os.path.exists(results_file):
        raise FileNotFoundError(f"Results file not found: {results_file}")

    runs = []
    with open(results_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            run = ExperimentRun(
                run_id=int(row['run']),
                checkpoint_ms=float(row['checkpoint_ms']),
                restore_ms=float(row['restore_ms']),
                idle_duration_s=float(row['idle_duration_s']),
                c6_residency_percent=float(row['c6_residency_percent'])
            )
            runs.append(run)

    # Load baseline C6 if available
    baseline_c6 = load_baseline_c6(results_dir)

    return ExperimentResults(runs=runs, baseline_c6=baseline_c6)


def load_baseline_c6(results_dir: str) -> Optional[float]:
    """Load baseline C6 residency from monitoring file"""
    baseline_file = os.path.join(results_dir, "baseline_c6.csv")

    if not os.path.exists(baseline_file):
        return None

    values = []
    with open(baseline_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Extract C6 percentage columns
            for key in row.keys():
                if 'c6_percent' in key:
                    try:
                        values.append(float(row[key]))
                    except ValueError:
                        pass

    return statistics.mean(values) if values else None


def calculate_energy_savings(results: ExperimentResults,
                              server_power_w: float = 100,
                              c6_power_reduction: float = 0.85) -> Dict:
    """
    Calculate estimated energy savings from checkpointing

    Args:
        results: Experiment results
        server_power_w: Server power consumption in watts
        c6_power_reduction: Power reduction when in C6 state (0.85 = 85%)

    Returns:
        Dictionary with energy analysis metrics
    """
    idle_duration_s = results.runs[0].idle_duration_s if results.runs else 0

    # Energy consumed during checkpoint/restore overhead (Joules = Watts * seconds)
    overhead_energy_j = server_power_w * (results.total_overhead_ms / 1000)

    # Energy saved during idle period in C6 state
    c6_savings_fraction = results.avg_c6_residency / 100
    idle_energy_saved_j = server_power_w * c6_power_reduction * idle_duration_s * c6_savings_fraction

    # Net energy savings
    net_savings_j = idle_energy_saved_j - overhead_energy_j

    # Break-even idle time (minimum idle duration for positive savings)
    if c6_savings_fraction > 0:
        break_even_s = (results.total_overhead_ms / 1000) / (c6_power_reduction * c6_savings_fraction)
    else:
        break_even_s = float('inf')

    return {
        'overhead_energy_j': overhead_energy_j,
        'idle_energy_saved_j': idle_energy_saved_j,
        'net_savings_j': net_savings_j,
        'net_savings_percent': (net_savings_j / (server_power_w * idle_duration_s)) * 100 if idle_duration_s > 0 else 0,
        'break_even_idle_s': break_even_s,
        'c6_improvement_percent': results.avg_c6_residency - (results.baseline_c6 or 0)
    }


def print_report(results: ExperimentResults, results_dir: str):
    """Print formatted analysis report"""
    print("\n" + "=" * 60)
    print("  ENERGY PROPORTIONALITY EXPERIMENT ANALYSIS")
    print("=" * 60)

    print(f"\nResults Directory: {results_dir}")
    print(f"Number of Runs: {len(results.runs)}")

    print("\n" + "-" * 60)
    print("  CHECKPOINT/RESTORE PERFORMANCE")
    print("-" * 60)

    print(f"\n  Checkpoint Latency:")
    valid_ckpt = [r.checkpoint_ms for r in results.runs if r.checkpoint_ms > 0]
    if valid_ckpt:
        print(f"    Average: {results.avg_checkpoint_ms:.1f} ms")
        print(f"    Min: {min(valid_ckpt):.1f} ms")
        print(f"    Max: {max(valid_ckpt):.1f} ms")
        if len(valid_ckpt) > 1:
            print(f"    Std Dev: {statistics.stdev(valid_ckpt):.1f} ms")
    else:
        print("    No successful checkpoints")

    print(f"\n  Restore Latency:")
    valid_rest = [r.restore_ms for r in results.runs if r.restore_ms > 0]
    if valid_rest:
        print(f"    Average: {results.avg_restore_ms:.1f} ms")
        print(f"    Min: {min(valid_rest):.1f} ms")
        print(f"    Max: {max(valid_rest):.1f} ms")
        if len(valid_rest) > 1:
            print(f"    Std Dev: {statistics.stdev(valid_rest):.1f} ms")
    else:
        print("    No successful restores")

    print(f"\n  Total Overhead: {results.total_overhead_ms:.1f} ms")

    print("\n" + "-" * 60)
    print("  C6 STATE RESIDENCY")
    print("-" * 60)

    print(f"\n  During Checkpoint Experiments:")
    print(f"    Average C6 Residency: {results.avg_c6_residency:.2f}%")

    if results.baseline_c6 is not None:
        print(f"\n  Baseline (No Checkpointing):")
        print(f"    C6 Residency: {results.baseline_c6:.2f}%")
        improvement = results.avg_c6_residency - results.baseline_c6
        print(f"    Improvement: {improvement:+.2f}%")

    print("\n" + "-" * 60)
    print("  ENERGY ANALYSIS")
    print("-" * 60)

    energy = calculate_energy_savings(results)

    print(f"\n  Assumptions:")
    print(f"    Server Power: 100W")
    print(f"    C6 Power Reduction: 85%")
    print(f"    Idle Duration: {results.runs[0].idle_duration_s if results.runs else 0}s")

    print(f"\n  Energy Metrics:")
    print(f"    Checkpoint/Restore Overhead: {energy['overhead_energy_j']:.2f} J")
    print(f"    Energy Saved During Idle: {energy['idle_energy_saved_j']:.2f} J")
    print(f"    Net Energy Savings: {energy['net_savings_j']:.2f} J ({energy['net_savings_percent']:.1f}%)")

    print(f"\n  Break-even Analysis:")
    if energy['break_even_idle_s'] < float('inf'):
        print(f"    Minimum Idle Duration for Savings: {energy['break_even_idle_s']:.2f}s")
    else:
        print(f"    Break-even: Cannot determine (no C6 residency)")

    print("\n" + "-" * 60)
    print("  PER-RUN DETAILS")
    print("-" * 60)

    print(f"\n  {'Run':<5} {'Checkpoint':<12} {'Restore':<12} {'C6%':<10}")
    print(f"  {'-'*5} {'-'*12} {'-'*12} {'-'*10}")

    for run in results.runs:
        ckpt = f"{run.checkpoint_ms:.0f}ms" if run.checkpoint_ms > 0 else "FAILED"
        rest = f"{run.restore_ms:.0f}ms" if run.restore_ms > 0 else "FAILED"
        print(f"  {run.run_id:<5} {ckpt:<12} {rest:<12} {run.c6_residency_percent:<10.2f}")

    print("\n" + "=" * 60)


def export_summary(results: ExperimentResults, output_file: str):
    """Export summary statistics to CSV"""
    energy = calculate_energy_savings(results)

    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['metric', 'value', 'unit'])
        writer.writerow(['num_runs', len(results.runs), 'count'])
        writer.writerow(['avg_checkpoint_ms', results.avg_checkpoint_ms, 'ms'])
        writer.writerow(['avg_restore_ms', results.avg_restore_ms, 'ms'])
        writer.writerow(['total_overhead_ms', results.total_overhead_ms, 'ms'])
        writer.writerow(['avg_c6_residency', results.avg_c6_residency, '%'])
        writer.writerow(['baseline_c6', results.baseline_c6 or 0, '%'])
        writer.writerow(['net_energy_savings_j', energy['net_savings_j'], 'J'])
        writer.writerow(['net_energy_savings_percent', energy['net_savings_percent'], '%'])
        writer.writerow(['break_even_idle_s', energy['break_even_idle_s'], 's'])

    print(f"\nSummary exported to: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Analyze energy proportionality experiment results'
    )
    parser.add_argument(
        'results_dir',
        help='Directory containing experiment results'
    )
    parser.add_argument(
        '--export', '-e',
        help='Export summary to CSV file'
    )
    parser.add_argument(
        '--server-power', '-p',
        type=float,
        default=100,
        help='Server power consumption in watts (default: 100)'
    )

    args = parser.parse_args()

    if not os.path.isdir(args.results_dir):
        print(f"Error: Directory not found: {args.results_dir}")
        sys.exit(1)

    try:
        results = load_results(args.results_dir)
        print_report(results, args.results_dir)

        if args.export:
            export_summary(results, args.export)

    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error analyzing results: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
