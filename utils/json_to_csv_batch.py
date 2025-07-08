# json_to_csv_batch.py
import os
import json
import csv
import argparse
from statistics import quantiles
from collections import defaultdict
from datetime import datetime

# รับ argument
parser = argparse.ArgumentParser(description='Convert k6 JSON to CSV for ingress controllers.')
parser.add_argument('ingress', help='Ingress controller name or "all"')
args = parser.parse_args()

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RESULT_DIR = os.path.join(ROOT_DIR, 'results')
IMPLEMENTATIONS = ['nginx', 'traefik', 'haproxy', 'apisix']

targets = IMPLEMENTATIONS if args.ingress.lower() == 'all' else [args.ingress]

for impl in targets:
    json_dir = os.path.join(RESULT_DIR, impl, 'json')
    csv_dir = os.path.join(RESULT_DIR, impl, 'csv')

    if not os.path.isdir(json_dir):
        print(f"⚠️  Skipped: {json_dir} not found")
        continue

    os.makedirs(csv_dir, exist_ok=True)

    for fname in os.listdir(json_dir):
        if not fname.endswith('.json'):
            continue

        filepath = os.path.join(json_dir, fname)
        outname = fname.replace('_json.json', '_csv.csv')
        outpath = os.path.join(csv_dir, outname)

        with open(filepath) as f:
            lines = [json.loads(line) for line in f if line.strip()]

        latency_data = defaultdict(list)
        error_count = defaultdict(int)
        request_count = defaultdict(int)

        for point in lines:
            if point.get('type') != 'Point':
                continue

            metric = point.get('metric')
            time_str = point['data']['time']
            dt = datetime.fromisoformat(time_str.split('+')[0])
            bucket = int(dt.timestamp() // 5) * 5

            if metric == 'http_req_duration':
                latency_data[bucket].append(point['data']['value'])

            if metric == 'errors' and point['data']['value'] > 0:
                error_count[bucket] += 1

            if metric == 'http_reqs':
                request_count[bucket] += point['data']['value']

        with open(outpath, 'w', newline='') as out:
            writer = csv.DictWriter(out, fieldnames=[
                'time_bucket_sec', 'avg_latency_ms', 'p99_latency_ms', 'rps', 'error_rate'
            ])
            writer.writeheader()

            for bucket in sorted(latency_data.keys()):
                data = latency_data[bucket]
                rps = request_count.get(bucket, 0) / 5
                errors = error_count.get(bucket, 0)
                total = request_count.get(bucket, 0)
                error_rate = (errors / total * 100) if total else 0

                writer.writerow({
                    'time_bucket_sec': datetime.fromtimestamp(bucket).isoformat(),
                    'avg_latency_ms': round(sum(data) / len(data), 2),
                    'p99_latency_ms': round(quantiles(data, n=100)[98], 2) if len(data) >= 2 else data[0],
                    'rps': round(rps, 2),
                    'error_rate': round(error_rate, 2),
                })

        print(f"✅ Generated: {outpath}")
