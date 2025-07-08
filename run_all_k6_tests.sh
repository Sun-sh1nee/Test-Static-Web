#!/bin/bash
set -euo pipefail

# ถ้าไม่ใส่อะไรจะรันทั้งหมด (default)
if [ "$#" -eq 0 ]; then
  INGRESSES=("nginx" "apisix" "traefik" "haproxy")
else
  INGRESSES=("$@")
fi

echo "♻️ [0/8] Cleaning up previous test runs..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  echo "🧹 Cleaning namespace $ns..."
  kubectl delete testrun.k6.io --all -n "$ns" --ignore-not-found
  kubectl delete configmap "k6-${ingress}-script" -n "$ns" --ignore-not-found
  kubectl delete namespace "$ns" --ignore-not-found
done

echo "🚀 [1/8] Creating namespaces..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "🛠️ [2/8] Generating fresh ConfigMaps from scripts/load_test.js..."
for ingress in "${INGRESSES[@]}"; do
  kubectl create configmap "k6-${ingress}-script" \
    --from-file=scripts/load_test.js \
    -n "k6-tests-${ingress}" \
    --dry-run=client -o yaml > "k6-crds/configmap-${ingress}.yaml"
done

echo "📥 [3/8] Applying ConfigMaps and K6 CRDs..."
for ingress in "${INGRESSES[@]}"; do
  echo "🔧 $ingress"
  kubectl apply -f "k6-crds/configmap-$ingress.yaml"
  kubectl apply -f "k6-crds/k6-$ingress.yaml"
done

echo "⏳ [4/8] Waiting for all tests to complete..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  while true; do
    statuses=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].status.phase}')
    still_running=0
    for status in $statuses; do
      if [[ "$status" == "Running" || "$status" == "Pending" ]]; then
        still_running=1
        break
      fi
    done

    if [[ $still_running -eq 1 ]]; then
      echo "⌛ $ingress test is still running or pending..."
      sleep 10
    else
      break
    fi
  done
  echo "✅ $ingress test completed."
done

echo "📁 [5/8] Getting logs as JSON output from all pods..."
for ingress in "${INGRESSES[@]}"; do
  ns="k6-tests-$ingress"
  mkdir -p "results/$ingress/json" "results/$ingress/csv"
  pods=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].metadata.name}')
  for pod in $pods; do
    echo "📥 Getting logs from pod $pod"
    kubectl logs -n "$ns" "$pod" > "results/$ingress/json/${pod}_json.json" || \
      echo "⚠️ Failed to get logs from $pod"
  done
done

echo "📊 [6/8] Converting JSON to CSV..."
for ingress in "${INGRESSES[@]}"; do
  python3 utils/json_to_csv_batch.py "$ingress"
done

echo "📈 [7/8] Aggregating summaries..."
for ingress in "${INGRESSES[@]}"; do
  python3 utils/aggregate_csv.py "$ingress"
done

echo "🎉 All ingress test workflows completed successfully!"

