#!/bin/bash

# LLM-D Well-Lit Path Test Script
# This script tests the deployed inference scheduling stack

set -e

# Default values
NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
MODEL_NAME=${MODEL_NAME:-"meta-llama/Llama-3.1-8B-Instruct"}
PORT=${PORT:-8080}
TIMEOUT=${TIMEOUT:-300}

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

function check_deployment_status() {
    log "Checking deployment status..."
    
    echo "=== Helm Releases ==="
    helm list -n ${NAMESPACE}
    
    echo -e "\n=== Pod Status ==="
    oc get pods -n ${NAMESPACE}
    
    echo -e "\n=== Services ==="
    oc get svc -n ${NAMESPACE}
    
    # Check if pods are running
    local running_pods=$(oc get pods -n ${NAMESPACE} --field-selector=status.phase=Running --no-headers | wc -l)
    local total_pods=$(oc get pods -n ${NAMESPACE} --no-headers | wc -l)
    
    log "Running pods: ${running_pods}/${total_pods}"
    
    if [[ ${running_pods} -eq 0 ]]; then
        error "No pods are running. Deployment may have failed."
        return 1
    fi
}

function wait_for_model_ready() {
    log "Waiting for model to be ready (timeout: ${TIMEOUT}s)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + TIMEOUT))
    
    while [[ $(date +%s) -lt ${end_time} ]]; do
        # Check if vLLM pods are ready
        local ready_pods=$(oc get pods -n ${NAMESPACE} -l llm-d.ai/inferenceServing=true --no-headers | grep "Running" | grep "1/1\|2/2" | wc -l)
        
        if [[ ${ready_pods} -gt 0 ]]; then
            log "Model pods are ready!"
            return 0
        fi
        
        echo -n "."
        sleep 10
    done
    
    echo
    error "Timeout waiting for model to be ready"
    return 1
}

function setup_port_forward() {
    log "Setting up port forwarding..."
    
    # Kill any existing port forward
    pkill -f "port-forward.*${PORT}" 2>/dev/null || true
    
    # Start new port forward in background
    oc port-forward ms-inference-scheduling-llm-d-modelservice-decode-757c597fxf7n7 ${PORT}:8000 -n ${NAMESPACE} &
    local pf_pid=$!
    
    # Wait for port forward to be ready
    sleep 5
    
    # Check if port forward is working
    if ! kill -0 $pf_pid 2>/dev/null; then
        error "Port forward failed to start"
        return 1
    fi
    
    log "Port forward active on localhost:${PORT} (PID: $pf_pid)"
    echo $pf_pid > /tmp/llm-d-port-forward.pid
}

function test_health_endpoint() {
    log "Testing health endpoint..."
    
    local response=$(curl -s -w "%{http_code}" -o /tmp/health_response.json "http://localhost:${PORT}/health" || echo "000")
    
    if [[ "$response" == "200" ]]; then
        log "Health check passed"
        return 0
    else
        error "Health check failed (HTTP $response)"
        return 1
    fi
}

function test_inference() {
    log "Testing inference endpoint..."
    
    local test_payload='{
        "model": "'${MODEL_NAME}'",
        "messages": [
            {
                "role": "user",
                "content": "Hello! Can you tell me about GPU acceleration in a few words?"
            }
        ],
        "max_tokens": 50,
        "temperature": 0.7
    }'
    
    log "Sending test request..."
    local response=$(curl -s -w "%{http_code}" -X POST "http://localhost:${PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        -o /tmp/inference_response.json || echo "000")
    
    if [[ "$response" == "200" ]]; then
        log "Inference test passed"
        echo "Response:"
        cat /tmp/inference_response.json | jq '.choices[0].message.content' 2>/dev/null || cat /tmp/inference_response.json
        return 0
    else
        error "Inference test failed (HTTP $response)"
        echo "Response:"
        cat /tmp/inference_response.json 2>/dev/null || echo "No response body"
        return 1
    fi
}

function cleanup_port_forward() {
    if [[ -f /tmp/llm-d-port-forward.pid ]]; then
        local pf_pid=$(cat /tmp/llm-d-port-forward.pid)
        kill $pf_pid 2>/dev/null || true
        rm -f /tmp/llm-d-port-forward.pid
        log "Port forward stopped"
    fi
}

function run_performance_test() {
    log "Running performance test (5 concurrent requests)..."
    
    local test_payload='{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Count from 1 to 10"}],
        "max_tokens": 30,
        "temperature": 0.1
    }'
    
    local start_time=$(date +%s)
    
    # Run 5 concurrent requests
    for i in {1..5}; do
        {
            local response=$(curl -s -w "%{http_code}" -X POST "http://localhost:${PORT}/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "$test_payload" \
                -o /tmp/perf_response_$i.json || echo "000")
            echo "Request $i: HTTP $response"
        } &
    done
    
    wait
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "Performance test completed in ${duration} seconds"
    
    # Count successful responses
    local success_count=0
    for i in {1..5}; do
        if [[ -f /tmp/perf_response_$i.json ]] && jq -e '.choices[0].message.content' /tmp/perf_response_$i.json >/dev/null 2>&1; then
            ((success_count++))
        fi
    done
    
    log "Successful responses: ${success_count}/5"
    
    # Cleanup temp files
    rm -f /tmp/perf_response_*.json
}

function show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test LLM-D inference scheduling deployment.

OPTIONS:
    -n, --namespace NAMESPACE    Target namespace (default: llm-d-inference-scheduling)
    -m, --model MODEL_NAME       Model name for testing (default: meta-llama/Llama-3.1-8B-Instruct)
    -p, --port PORT             Local port for port forwarding (default: 8080)
    -t, --timeout TIMEOUT       Timeout in seconds (default: 300)
    --perf                      Run performance test
    --skip-wait                 Skip waiting for model ready
    -h, --help                  Show this help message

EXAMPLES:
    # Basic test
    ./test.sh

    # Test with different model
    ./test.sh --model "Qwen/Qwen3-0.6B"

    # Run performance test
    ./test.sh --perf

ENVIRONMENT VARIABLES:
    NAMESPACE                   Target namespace (default: llm-d-inference-scheduling)
    MODEL_NAME                  Model name for testing
    PORT                        Local port for port forwarding
    TIMEOUT                     Timeout in seconds
EOF
}

# Parse command line arguments
SKIP_WAIT=false
RUN_PERF=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -m|--model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --perf)
            RUN_PERF=true
            shift
            ;;
        --skip-wait)
            SKIP_WAIT=true
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

# Trap to cleanup on exit
trap cleanup_port_forward EXIT

# Main test flow
log "Starting LLM-D inference scheduling tests..."
log "Namespace: ${NAMESPACE}"
log "Model: ${MODEL_NAME}"
log "Port: ${PORT}"

check_deployment_status

if [[ "${SKIP_WAIT}" != "true" ]]; then
    wait_for_model_ready
fi

setup_port_forward
sleep 3  # Give port forward time to stabilize

test_health_endpoint
test_inference

if [[ "${RUN_PERF}" == "true" ]]; then
    run_performance_test
fi

log "All tests completed successfully!"
log "Inference scheduling is working correctly" 