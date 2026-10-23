#!/bin/bash
# Simple Kubernetes Pruner using kubectl built-in commands

set -e

# Configuration
NAMESPACE="${1:-default}"
DRY_RUN="${2:-true}"

echo "Pruning unused resources in namespace: $NAMESPACE"

if [ "$DRY_RUN" = "true" ]; then
    DRY_RUN_FLAG="--dry-run=client"
    echo "Running in dry-run mode"
else
    DRY_RUN_FLAG=""
fi

# 1. Delete failed pods
echo "Cleaning failed pods..."
kubectl delete pods -n $NAMESPACE --field-selector=status.phase=Failed $DRY_RUN_FLAG

# 2. Delete completed pods (from Jobs)
echo "Cleaning completed pods..."
kubectl delete pods -n $NAMESPACE --field-selector=status.phase=Succeeded $DRY_RUN_FLAG

# 3. Delete orphaned ReplicaSets (with 0 replicas)
echo "Cleaning orphaned ReplicaSets..."
kubectl get replicasets -n $NAMESPACE -o json | \
  jq -r '.items[] | select(.metadata.ownerReferences == null) | select(.spec.replicas == 0) | .metadata.name' | \
  xargs -r kubectl delete replicasets -n $NAMESPACE $DRY_RUN_FLAG

# 4. Delete old Completed Jobs (older than 1 day)
echo "Cleaning old completed jobs..."
kubectl delete jobs -n $NAMESPACE --field-selector=status.successful=1 $DRY_RUN_FLAG

# 5. Clean up Evicted pods
echo "Cleaning evicted pods..."
kubectl get pods -n $NAMESPACE | grep Evicted | awk '{print $1}' | xargs -r kubectl delete pod -n $NAMESPACE $DRY_RUN_FLAG

# 6. Clean up ImagePullBackOff pods
echo "Cleaning ImagePullBackOff pods..."
kubectl get pods -n $NAMESPACE | grep ImagePullBackOff | awk '{print $1}' | xargs -r kubectl delete pod -n $NAMESPACE $DRY_RUN_FLAG

# 7. Clean up ErrImagePull pods
echo "Cleaning ErrImagePull pods..."
kubectl get pods -n $NAMESPACE | grep ErrImagePull | awk '{print $1}' | xargs -r kubectl delete pod -n $NAMESPACE $DRY_RUN_FLAG

echo "Cleanup completed!"
