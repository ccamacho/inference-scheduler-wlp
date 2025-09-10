#!/bin/bash

# LLM-D Well-Lit Path Cleanup Script
# This script removes all components deployed by the inference scheduling stack

set -e

# Default values
NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
FORCE=${FORCE:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function confirm_cleanup() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    warn "This will remove all LLM-D inference scheduling components from namespace: ${NAMESPACE}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
}

function cleanup_helm_releases() {
    log "Removing Helm releases..."
    
    # Remove model service
    helm uninstall ms-inference-scheduling -n ${NAMESPACE} 2>/dev/null || warn "ms-inference-scheduling release not found"
    
    # Remove GAIE scheduler
    helm uninstall gaie-inference-scheduling -n ${NAMESPACE} 2>/dev/null || warn "gaie-inference-scheduling release not found"
    
    # Remove infrastructure
    helm uninstall infra-inference-scheduling -n ${NAMESPACE} 2>/dev/null || warn "infra-inference-scheduling release not found"
}

function cleanup_resources() {
    log "Removing Kubernetes resources..."
    
    # Remove HTTPRoute
    oc delete httproute llm-d-inference-scheduling -n ${NAMESPACE} 2>/dev/null || warn "HTTPRoute not found"
    
    # Remove PVC
    oc delete pvc llama-model-storage -n ${NAMESPACE} 2>/dev/null || warn "PVC not found"
    
    # Remove secrets
    oc delete secret llm-d-hf-token -n ${NAMESPACE} 2>/dev/null || warn "Secret not found"
}

function cleanup_namespace() {
    if [[ "${FORCE}" == "true" ]] || [[ "$1" == "--remove-namespace" ]]; then
        log "Removing namespace ${NAMESPACE}..."
        oc delete namespace ${NAMESPACE} 2>/dev/null || warn "Namespace not found or not empty"
    else
        log "Namespace ${NAMESPACE} preserved (use --remove-namespace to delete)"
    fi
}

function show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up LLM-D inference scheduling deployment.

OPTIONS:
    -n, --namespace NAMESPACE    Target namespace (default: llm-d-inference-scheduling)
    -f, --force                 Skip confirmation prompts
    --remove-namespace          Also remove the namespace
    -h, --help                  Show this help message

EXAMPLES:
    # Clean up with confirmation
    ./cleanup.sh

    # Force cleanup without prompts
    ./cleanup.sh --force

    # Clean up and remove namespace
    ./cleanup.sh --remove-namespace

ENVIRONMENT VARIABLES:
    NAMESPACE                   Target namespace (default: llm-d-inference-scheduling)
    FORCE                       Skip confirmations (default: false)
EOF
}

# Parse command line arguments
REMOVE_NAMESPACE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --remove-namespace)
            REMOVE_NAMESPACE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main cleanup flow
log "Starting LLM-D inference scheduling cleanup..."
log "Namespace: ${NAMESPACE}"

confirm_cleanup
cleanup_helm_releases
cleanup_resources

if [[ "${REMOVE_NAMESPACE}" == "true" ]]; then
    cleanup_namespace --remove-namespace
else
    cleanup_namespace
fi

log "Cleanup completed successfully!" 