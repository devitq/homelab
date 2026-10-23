#!/bin/bash

# Kubernetes Resource Pruner Script
# Safely removes unused resources from Kubernetes clusters

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
DRY_RUN=true
NAMESPACE=""
ALL_NAMESPACES=false
FORCE=false
# RESOURCE_TYPES=("rs" "pod" "pv" "pvc" "cm" "secret" "job" "hpa" "ingress" "svc")
RESOURCE_TYPES=("rs" "pod" "pv" "pvc" "job" "hpa" "ingress")

# Function to print colored output
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Kubernetes Resource Pruner - Removes unused resources from Kubernetes clusters

Options:
    -n, --namespace NAME     Target specific namespace (default: current context namespace)
    -A, --all-namespaces     Process all namespaces
    -f, --force              Actually delete resources (default: dry-run)
    -t, --type RESOURCE      Specific resource types to prune (comma-separated)
                             Available: rs,pod,pv,pvc,cm,secret,job,hpa,ingress,svc
    -h, --help               Show this help message

Examples:
    $0                          # Dry run in current namespace
    $0 -n my-namespace -f       # Actually delete in specific namespace
    $0 -A -f                    # Delete in all namespaces
    $0 -t "rs,pod,job" -f       # Only prune replicasets, pods, and jobs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -A|--all-namespaces)
            ALL_NAMESPACES=true
            shift
            ;;
        -f|--force)
            DRY_RUN=false
            shift
            ;;
        -t|--type)
            IFS=',' read -ra RESOURCE_TYPES <<< "$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set namespace flags
if [ "$ALL_NAMESPACES" = true ]; then
    NS_FLAG="--all-namespaces"
    NS_TEXT="all namespaces"
elif [ -n "$NAMESPACE" ]; then
    NS_FLAG="-n $NAMESPACE"
    NS_TEXT="namespace: $NAMESPACE"
else
    NS_FLAG=""
    NS_TEXT="current namespace"
fi

# Function to get resources with namespace
get_resources() {
    local resource=$1
    local namespace_flag=$2
    kubectl get $resource $namespace_flag --no-headers 2>/dev/null || echo ""
}

# Function to delete resource
delete_resource() {
    local resource=$1
    local name=$2
    local namespace=$3
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete $resource/$name in $namespace"
    else
        log_warning "Deleting $resource/$name in $namespace"
        if [ -n "$namespace" ] && [ "$namespace" != "NAMESPACE" ]; then
            kubectl delete $resource "$name" -n "$namespace" --wait=false
        else
            kubectl delete $resource "$name" --wait=false
        fi
        sleep 0.5 # Small delay to avoid API rate limiting
    fi
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check Kubernetes connection
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log_info "Starting Kubernetes resource pruning in $NS_TEXT"
if [ "$DRY_RUN" = true ]; then
    log_warning "RUNNING IN DRY-RUN MODE - No resources will be deleted"
    log_warning "Use -f flag to actually delete resources"
fi

# Prune Pods (Failed, Evicted, Completed, ImagePullBackOff, ErrImagePull)
if [[ " ${RESOURCE_TYPES[@]} " =~ " pod " ]]; then
    log_info "Checking for non-running Pods..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name ready status restarts age <<< "$line"
        
        # Check pod status
        pod_status=$(echo "$status" | tr '[:upper:]' '[:lower:]')
        case $pod_status in
            *failed*|*evicted*|*completed*|*imagepullbackoff*|*errimagepull*|*crashloopbackoff*|*error*)
                # Check if pod is managed by a controller
                owner=$(kubectl get pod "$name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
                delete_resource "pod" "$name" "$namespace"
                # if [[ "$owner" ]]; then
                #     delete_resource "pod" "$name" "$namespace"
                # fi
                ;;
        esac
    done < <(get_resources "pod" "$NS_FLAG")
fi

# Prune ReplicaSets (orphaned and with 0 replicas)
if [[ " ${RESOURCE_TYPES[@]} " =~ " rs " ]]; then
    log_info "Checking for unused ReplicaSets..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name replicas desired ready age <<< "$line"
        if [[ "$desired" == "0" ]] || [[ "$ready" == "0" && "$desired" == "0" ]]; then
            delete_resource "rs" "$name" "$namespace"
            # Check if owned by a Deployment
            # owner=$(kubectl get rs "$name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
            # if [[ -z "$owner" ]] || [[ "$owner" != "Deployment" ]]; then
            #     delete_resource "rs" "$name" "$namespace"
            # fi
        fi
    done < <(get_resources "rs" "$NS_FLAG")
fi

# Prune PersistentVolumeClaims (in Released state)
if [[ " ${RESOURCE_TYPES[@]} " =~ " pvc " ]]; then
    log_info "Checking for unused PersistentVolumeClaims..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name status capacity accessmodes storageclass age <<< "$line"
        if [[ "$status" == "Released" ]] || [[ "$status" == "Available" ]]; then
            delete_resource "pvc" "$name" "$namespace"
        fi
    done < <(get_resources "pvc" "$NS_FLAG")
fi

# Prune PersistentVolumes (in Released/Available state)
if [[ " ${RESOURCE_TYPES[@]} " =~ " pv " ]]; then
    log_info "Checking for unused PersistentVolumes..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r name capacity accessmodes reclaimstatus status storageclass reason age <<< "$line"
        if [[ "$status" == "Released" ]] || [[ "$status" == "Available" ]]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would delete pv/$name"
            else
                log_warning "Deleting pv/$name"
                kubectl delete pv "$name"
            fi
        fi
    done < <(kubectl get pv --no-headers 2>/dev/null || echo "")
fi

# Prune ConfigMaps (check if they're being used)
if [[ " ${RESOURCE_TYPES[@]} " =~ " cm " ]]; then
    log_info "Checking for unused ConfigMaps..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name data age <<< "$line"
        
        # Skip system configmaps
        if [[ "$name" == kube-root-ca.crt ]] || \
           [[ "$name" == kube-proxy ]] || \
           [[ "$name" == extension-apiserver-authentication ]] || \
           [[ "$namespace" == "kube-system" ]]; then
            continue
        fi
        
        # Check if any pod is using this configmap
        if ! kubectl get pods $NS_FLAG -o yaml | grep -q "configMapKeyRef:\|configMapRef:" 2>/dev/null; then
            # Simple check - in production you might want more sophisticated checks
            delete_resource "configmap" "$name" "$namespace"
        fi
    done < <(get_resources "configmap" "$NS_FLAG")
fi

# Prune Secrets (check if they're being used)
if [[ " ${RESOURCE_TYPES[@]} " =~ " secret " ]]; then
    log_info "Checking for unused Secrets..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name type data age <<< "$line"
        
        # Skip system secrets
        if [[ "$name" == *token ]] || \
           [[ "$type" == *service-account* ]] || \
           [[ "$namespace" == "kube-system" ]]; then
            continue
        fi
        
        # Check if any pod is using this secret
        if ! kubectl get pods $NS_FLAG -o yaml | grep -q "secretKeyRef:\|secretRef:" 2>/dev/null; then
            delete_resource "secret" "$name" "$namespace"
        fi
    done < <(get_resources "secret" "$NS_FLAG")
fi

# Prune completed Jobs
if [[ " ${RESOURCE_TYPES[@]} " =~ " job " ]]; then
    log_info "Checking for completed Jobs..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name completions duration age <<< "$line"
        
        # Get job completion status
        job_info=$(kubectl get job "$name" -n "$namespace" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        if [[ "$job_info" == "1" ]] || [[ "$age" =~ d$ ]] && [[ "$age" > "1d" ]]; then
            delete_resource "job" "$name" "$namespace"
        fi
    done < <(get_resources "job" "$NS_FLAG")
fi

# Prune unused Services
if [[ " ${RESOURCE_TYPES[@]} " =~ " svc " ]]; then
    log_info "Checking for unused Services..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name type clusterip externalip ports age <<< "$line"
        
        # Skip system services
        if [[ "$name" == kubernetes ]] || \
           [[ "$namespace" == "kube-system" ]] || \
           [[ "$type" == *LoadBalancer* ]]; then
            continue
        fi
        
        # Check if service has no endpoints
        endpoints=$(kubectl get endpoints "$name" -n "$namespace" -o jsonpath='{.subsets}' 2>/dev/null || echo "")
        if [[ -z "$endpoints" ]] || [[ "$endpoints" == "null" ]] || [[ "$endpoints" == "[]" ]]; then
            delete_resource "service" "$name" "$namespace"
        fi
    done < <(get_resources "service" "$NS_FLAG")
fi

# Prune unused Ingresses
if [[ " ${RESOURCE_TYPES[@]} " =~ " ingress " ]]; then
    log_info "Checking for unused Ingresses..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name class hosts address ports age <<< "$line"
        
        # Check if there are no backend services
        backends=$(kubectl get ingress "$name" -n "$namespace" -o jsonpath='{.spec.rules[*].http.paths[*].backend.service.name}' 2>/dev/null || echo "")
        if [[ -z "$backends" ]]; then
            delete_resource "ingress" "$name" "$namespace"
        fi
    done < <(get_resources "ingress" "$NS_FLAG")
fi

# Prune unused HPAs with 0 replicas
if [[ " ${RESOURCE_TYPES[@]} " =~ " hpa " ]]; then
    log_info "Checking for unused HorizontalPodAutoscalers..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -r namespace name reference targets minpods maxpods replicas age <<< "$line"
        
        if [[ "$replicas" == "0" ]] && [[ "$minpods" == "0" ]]; then
            delete_resource "hpa" "$name" "$namespace"
        fi
    done < <(get_resources "hpa" "$NS_FLAG")
fi

# Final summary
if [ "$DRY_RUN" = true ]; then
    log_success "Dry run completed. Review the resources above."
    log_success "Run with -f flag to actually delete these resources."
else
    log_success "Resource pruning completed successfully!"
fi
