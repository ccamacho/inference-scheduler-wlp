#!/bin/bash

# LLM-D Inference Scheduling Helmfile Deployment Script
# This script deploys using the helmfile approach with proper namespace handling

set -e

# Default values
NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
ENVIRONMENT=${ENVIRONMENT:-default}
RELEASE_NAME_POSTFIX=${RELEASE_NAME_POSTFIX:-inference-scheduling}

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

function show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy LLM-D inference scheduling stack using helmfile.

OPTIONS:
    -n, --namespace NAMESPACE    Target namespace (default: llm-d-inference-scheduling)
    -e, --environment ENV        Helmfile environment (default: default)
                                Available: default, istio
    -r, --release-postfix NAME   Release name postfix (default: inference-scheduling)
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy with default configuration
    ./deploy-helmfile.sh

    # Deploy with Istio environment
    ./deploy-helmfile.sh --environment istio

    # Deploy to custom namespace
    ./deploy-helmfile.sh --namespace my-namespace

ENVIRONMENT VARIABLES:
    NAMESPACE                   Target namespace (default: llm-d-inference-scheduling)
    ENVIRONMENT                 Helmfile environment (default: default, available: istio)
    RELEASE_NAME_POSTFIX        Release name postfix (default: inference-scheduling)
    HF_TOKEN                    HuggingFace token (required)
EOF
}

function check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required environment variables
    if [[ -z "${HF_TOKEN}" ]]; then
        error "HF_TOKEN environment variable is not set"
        exit 1
    fi
    
    # Check required tools
    for tool in helmfile kubectl oc; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    log "Prerequisites check passed"
}

function create_namespace_and_secrets() {
    log "Creating namespace and secrets..."
    
    # Create namespace
    oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -
    
    # Create HuggingFace token secret
    oc create secret generic llm-d-hf-token \
        --from-literal=HF_TOKEN=${HF_TOKEN} \
        -n ${NAMESPACE} \
        --dry-run=client -o yaml | oc apply -f -
    
    # Create PVC for model storage
    log "Creating PVC for model storage..."
    sed "s/namespace: llm-d-inference-scheduling/namespace: ${NAMESPACE}/g" pvc.yaml | oc apply -f -
}

function deploy_with_helmfile() {
    log "Deploying with helmfile..."
    log "Namespace: ${NAMESPACE}"
    log "Environment: ${ENVIRONMENT}"
    log "Release name postfix: ${RELEASE_NAME_POSTFIX}"
    log "PodMonitor: enabled for monitoring"
    
    # Export release name postfix for helmfile
    export RELEASE_NAME_POSTFIX
    
    # Deploy using helmfile
    helmfile sync --environment ${ENVIRONMENT} --namespace ${NAMESPACE}
}

function install_httproute() {
    log "Installing HTTPRoute..."
    
    # Apply HTTPRoute with namespace substitution
    sed "s/namespace: llm-d-inference-scheduling/namespace: ${NAMESPACE}/g" httproute.yaml | oc apply -f -
}

function verify_deployment() {
    log "Verifying deployment..."
    
    echo "=== Helm Releases ==="
    helm list -n ${NAMESPACE}
    
    echo -e "\n=== Pod Status ==="
    oc get pods -n ${NAMESPACE}
    
    echo -e "\n=== Services ==="
    oc get svc -n ${NAMESPACE}
    
    echo -e "\n=== HTTPRoute Status ==="
    oc get httproutes -n ${NAMESPACE}
    
    echo -e "\n=== PodMonitor Status ==="
    oc get podmonitors -n ${NAMESPACE} 2>/dev/null || echo "No PodMonitors found (monitoring operator may not be installed)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--release-postfix)
            RELEASE_NAME_POSTFIX="$2"
            shift 2
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

# Main deployment flow
log "Starting LLM-D inference scheduling deployment with helmfile..."

check_prerequisites
create_namespace_and_secrets
deploy_with_helmfile
install_httproute
verify_deployment

log "Deployment completed successfully!"
log "You can now test the deployment using the test script in the parent directory." 