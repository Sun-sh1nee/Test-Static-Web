#!/bin/bash

set -e

# ถ้าไม่ใส่อะไรจะรันทั้งหมด (default)
if [ "$#" -eq 0 ]; then
  INGRESSES=("nginx" "apisix" "traefik" "haproxy")
else
  INGRESSES=("$@")
fi

echo "🚀 [1/7] Creating namespaces..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

echo "📥 [2/7] Applying ConfigMaps and K6 CRDs..."
for ingress in "${INGRESSES[@]}"; do
  echo "🔧 $ingress"
  kubectl apply -f k6-crds/configmap-$ingress.yaml
  kubectl apply -f k6-crds/k6-$ingress.yaml
done

echo "⏳ [3/7] Waiting for all tests to complete..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  while kubectl get pods -n "$ns" -l k6_cr=true 2>/dev/null | grep -q Running; do
    echo "⌛ $ingress test is still running..."
    sleep 10
  done
  echo "✅ $ingress test completed."
done

echo "📁 [4/7] Copying JSON output from all pods..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  mkdir -p results/$ingress/json results/$ingress/csv
  pods=$(kubectl get pods -n "$ns" -l k6_cr=true -o jsonpath='{.items[*].metadata.name}')
  for pod in $pods; do
    kubectl cp "$ns/$pod:/tests/output.json" "results/$ingress/json/${pod}_json.json"
  done
done

echo "📊 [5/7] Converting JSON to CSV..."
for ingress in "${INGRESSES[@]}"; do
  python3 utils/json_to_csv_batch.py $ingress
done

echo "📈 [6/7] Aggregating summaries..."
for ingress in "${INGRESSES[@]}"; do
  python3 utils/aggregate_csv.py $ingress
done

echo "📤 [7/7] Pushing results to GitHub..."
git add results/
git commit -m "Add k6 test results for ingress: ${INGRESSES[*]}"
git push

echo "🎉 All ingress test workflows completed successfully!"

