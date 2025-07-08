# aggregate_csv.py
import os
import csv
import argparse
from collections import defaultdict

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RESULT_DIR = os.path.join(ROOT_DIR, 'results')
IMPLEMENTATIONS = ['nginx', 'traefik', 'haproxy', 'apisix']

parser = argparse.ArgumentParser(description='Aggregate CSV results from multiple nodes.')
parser.add_argument('ingress', help='Ingress controller name or "all"')
args = parser.parse_args()

targets = IMPLEMENTATIONS if args.ingress.lower() == 'all' else [args.ingress]

def aggregate_controller(controller):
    csv_dir = os.path.join(RESULT_DIR, controller, 'csv')
    if not os.path.isdir(csv_dir):
        print(f"⚠️  Skipped: No CSV folder found for {controller} at {csv_dir}")
        return

    aggregated = defaultdict(lambda: defaultdict(list))
    files_found = False

    for fname in os.listdir(csv_dir):
        if not fname.endswith('.csv'):
            continue
        files_found = True
        filepath = os.path.join(csv_dir, fname)
        with open(filepath) as f:
            reader = csv.DictReader(f)
            for row in reader:
                bucket = row['time_bucket_sec']
                for key in ['avg_latency_ms', 'p99_latency_ms', 'rps', 'error_rate']:
                    try:
                        aggregated[bucket][key].append(float(row[key]))
                    except ValueError:
                        pass

    if not files_found:
        print(f"⚠️  No CSV files found for {controller} in {csv_dir}")
        return

    output_path = os.path.join(RESULT_DIR, controller, 'summary.csv')
    with open(output_path, 'w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=[
            'time_bucket_sec', 'avg_latency_ms', 'p99_latency_ms', 'rps', 'error_rate'
        ])
        writer.writeheader()
        for bucket in sorted(aggregated.keys()):
            row = {'time_bucket_sec': bucket}
            for key in ['avg_latency_ms', 'p99_latency_ms', 'rps', 'error_rate']:
                values = aggregated[bucket][key]
                if values:
                    row[key] = round(sum(values) / len(values), 2)
                else:
                    row[key] = ''
            writer.writerow(row)
    print(f"✅ Aggregated results saved to {output_path}")

for c in targets:
    aggregate_controller(c)
