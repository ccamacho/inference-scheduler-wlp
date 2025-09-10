# LLM-D Well-Lit Path: Inference Scheduling Deployment

> **📁 All deployment files and scripts are in the [`inference-scheduling/`](./inference-scheduling/) directory. Start there for deployment.**

## 🚀 Quick Start - Simplified Deployment

This well-lit path provides a streamlined helmfile-based approach to deploying intelligent inference
scheduling with LLM-D. All deployment files and scripts are located in the `inference-scheduling/` directory.

**✅ Tested Working Setup:**
- **Model**: [meta-llama/Llama-3.1-8B-Instruct](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct) (8.03B parameters)
- **Hardware**: 4x L40S GPUs (48GB each, 192GB total)
- **Configuration**: 4 replicas × TP=1 (single GPU per replica)
- **Context**: 4096 tokens (optimized for 8B model)
- **Storage**: 50Gi PVC with high-performance storage
- **Gateway**: Istio ClusterIP with precise prefix-cache-aware GAIE scheduling

**Key Success Factors:**
- Lightweight Llama-3.1-8B-Instruct model (8.03B parameters) for reliable deployment
- Single GPU per replica (TP=1) for stable multi-node deployment
- Precise prefix-cache-aware scheduling for maximum cache hit rates
- Persistent storage with PVC for model caching and fast restarts
- Advanced monitoring with PodMonitor integration
- ClusterIP services for reliable internal cluster communication

## Environment Setup

```bash
# Export required environment variables
export KUBECONFIG=~/my-kubeconfig-path
export NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
export HF_TOKEN=hf_your_huggingface_token_here
```

## Prerequisites

### 1. Install LeaderWorkerSet (LWS)
```bash
# Install LWS for advanced workload management
export LWS_CHART_VERSION=0.7.0
helm install lws oci://registry.k8s.io/lws/charts/lws \
    --version=${LWS_CHART_VERSION} \
    --namespace lws-system \
    --create-namespace \
    --wait --timeout 300s

# Wait for controller to be ready (takes ~8 minutes)
kubectl -n lws-system get deploy,po
kubectl wait deploy/lws-controller-manager -n lws-system --for=condition=available --timeout=8m

# Verify CRD installation
kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io
kubectl api-resources | grep -i leaderworker
```

### 2. Install Gateway Control Plane Providers
```bash
git clone https://github.com/llm-d-incubation/llm-d-infra.git
cd ./llm-d-infra/quickstart/gateway-control-plane-providers
./install-gateway-provider-dependencies.sh
```

### 3. Create Namespace and HuggingFace Token Secret
```bash
# Create namespace
oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -

# Create HuggingFace token secret
oc create secret generic llm-d-hf-token \
  --from-literal=HF_TOKEN=${HF_TOKEN} \
  -n ${NAMESPACE}
```

## Deployment

### Helmfile Deployment (Recommended)

This project uses a helmfile-based approach for infrastructure-style deployment. Navigate to the `inference-scheduling` directory:

```bash
cd inference-scheduling

# Use the automated helmfile deployment script (recommended)
./deploy-helmfile.sh

# Deploy with Istio environment
./deploy-helmfile.sh --environment istio

# Deploy to custom namespace
./deploy-helmfile.sh --namespace my-namespace

# Or use helmfile directly
helmfile sync --namespace ${NAMESPACE}

# Deploy with specific environment (e.g., Istio)
helmfile sync --environment istio --namespace ${NAMESPACE}

# Deploy with custom release name postfix
export RELEASE_NAME_POSTFIX=my-custom-name
helmfile sync --namespace ${NAMESPACE}
```

**Note**: The helmfile automatically uses the `--namespace` flag value or falls back to `llm-d-inference-scheduling` if not specified. The default environment uses Istio gateway configuration. All resources will be deployed to the specified namespace.

### Deployment Timeline

**Expected deployment phases:**
1. **Infrastructure (30-60s)**: Istio Gateway and basic networking
2. **GAIE Scheduler (30-60s)**: Intelligent inference routing (may require CRD installation)
3. **Model Service (5-15min)**: vLLM pods with model download (depends on GPU availability)

**GPU Initialization**: If GPU device plugins are not ready, model service pods will remain in `Pending` state until GPU nodes are available. This can take 5-10 minutes on first setup.

## Verification and Testing

### Check Deployment Status
```bash
echo "=== Helm Releases ==="
helm list -n ${NAMESPACE}

echo "=== Pod Status ==="
oc get pods -n ${NAMESPACE}

echo "=== PVC Status ==="
oc get pvc -n ${NAMESPACE}

echo "=== Services ==="
oc get svc -n ${NAMESPACE}

echo "=== HTTPRoute Status ==="
oc get httproutes -n ${NAMESPACE}
```

### Test Inference

#### Automated Testing (Recommended)
```bash
# Navigate to inference-scheduling directory
cd inference-scheduling

# Run comprehensive tests including health check and inference
./test.sh

# Run performance test with multiple concurrent requests
./test.sh --perf

# Test with different model
./test.sh --model "Qwen/Qwen3-32B"
```

#### Manual Testing
```bash
# Port forward to gateway
oc port-forward svc/infra-inference-scheduling-inference-gateway-istio 8080:80 -n ${NAMESPACE} &

# Test inference request
curl -X POST "http://localhost:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [
      {
        "role": "user", 
        "content": "Hello! Can you tell me about GPU acceleration?"
      }
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'

# Stop port forward
kill %1
```

## Configuration Options

### Different Models

To use different models, edit the `inference-scheduling/ms-inference-scheduling/values.yaml` file and change the model configuration, then redeploy:

```bash
cd inference-scheduling

# Edit the values file to change model
# vim ms-inference-scheduling/values.yaml

# Redeploy with helmfile
helmfile sync --namespace ${NAMESPACE}
```

### Scaling

To scale to multiple replicas, edit the `inference-scheduling/ms-inference-scheduling/values.yaml` file and change the replica count, then redeploy:

```bash
cd inference-scheduling

# Edit the values file to change replica count
# vim ms-inference-scheduling/values.yaml
# Change: decode.replicas: 4

# Redeploy with helmfile
helmfile sync --namespace ${NAMESPACE}
```

## Custom Scoring Algorithms (EPP Configuration)

The GAIE (Gateway API Inference Extension) supports multiple intelligent scheduling algorithms through EPP (Endpoint Picker Plugin) configuration. You can customize how requests are routed to different vLLM pods based on various scoring factors.

### Available Scorer Types

1. **Queue-Only Scoring**: Routes based on queue depth (currently active)
2. **Multi-Factor Scoring**: Combines queue + cache + prefix awareness  
3. **Round-Robin**: Simple load balancing without intelligence
4. **Default**: Built-in approximate prefix-cache-aware routing

### How to Change Scoring Configuration

Edit the GAIE configuration file:

```bash
cd inference-scheduling

# Edit the GAIE EPP configuration
vim gaie-inference-scheduling/values.yaml
```

**Example configurations:**

```yaml
# OPTION 1: Default plugins-v2.yaml (approximate prefix-cache)
pluginsConfigFile: "plugins-v2.yaml"

# OPTION 2: Custom multi-factor scoring
pluginsConfigFile: "custom-scorers.yaml"
pluginsCustomConfig:
  custom-scorers.yaml: |
    apiVersion: inference.networking.x-k8s.io/v1alpha1
    kind: EndpointPickerConfig
    plugins:
      - type: single-profile-handler
      - type: queue-scorer              # Queue depth scoring
      - type: kv-cache-scorer           # Cache utilization scoring
      - type: prefix-cache-scorer       # Prefix cache awareness
        parameters:
          mode: approximate             # or "cache_tracking"
      - type: max-score-picker          # Selection algorithm
    schedulingProfiles:
      - name: default
        plugins:
          - pluginRef: queue-scorer
            weight: 1.0                 # Adjust weights as needed
          - pluginRef: kv-cache-scorer
            weight: 2.0
          - pluginRef: prefix-cache-scorer
            weight: 3.0

# OPTION 3: Simple round-robin
pluginsConfigFile: "round-robin.yaml"
pluginsCustomConfig:
  round-robin.yaml: |
    apiVersion: inference.networking.x-k8s.io/v1alpha1
    kind: EndpointPickerConfig
    plugins:
      - type: single-profile-handler
      - type: round-robin-picker
    schedulingProfiles:
      - name: default
        plugins:
          - pluginRef: round-robin-picker
```

### Apply EPP Configuration Changes

After modifying the GAIE EPP configuration, apply the changes:

```bash
cd inference-scheduling

# Deploy only the GAIE component with new EPP configuration
helmfile sync --namespace ${NAMESPACE} --selector name=gaie-inference-scheduling

# Wait for new GAIE pod to start
oc get pods -n ${NAMESPACE} | grep gaie

# Test the new scoring algorithm
./test.sh
```

### Monitor Scorer Performance

Monitor how different scorers perform and make routing decisions:

```bash
# Check GAIE logs for scoring decisions
oc logs deployment/gaie-inference-scheduling-epp -n ${NAMESPACE} --tail=50

# Monitor endpoint metrics and scoring
oc port-forward svc/gaie-inference-scheduling-epp 9090:9090 -n ${NAMESPACE} &
curl http://localhost:9090/metrics | grep -E "score|queue|cache"

# Check individual pod queue depths and utilization
oc logs <model-pod-name> -c vllm -n ${NAMESPACE} | grep -E "queue|requests|utilization"
```

## Troubleshooting

### Common Issues

1. **Missing CRDs**: If deployment fails with "no matches for kind InferencePool", install the required CRDs:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api-inference-extension/main/config/crd/bases/inference.networking.x-k8s.io_inferencepools.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api-inference-extension/v0.5.1/config/crd/bases/inference.networking.x-k8s.io_inferencemodels.yaml
   ```

2. **GAIE Pod CrashLoopBackOff**: Usually caused by missing InferenceModel CRD. Install CRDs and restart:
   ```bash
   oc rollout restart deployment gaie-inference-scheduling-epp -n ${NAMESPACE}
   ```

3. **Pods Pending - Insufficient GPU**: Check GPU device plugin status:
   ```bash
   # Check GPU operator pods
   oc get pods -A | grep -i gpu
   
   # Check node GPU capacity (should show nvidia.com/gpu)
   oc describe node <gpu-node-name> | grep -A10 "Capacity:"
   
   # Wait for GPU device plugin initialization (can take 5-10 minutes)
   oc get pods -n nvidia-gpu-operator | grep device-plugin
   ```

4. **Gateway API CRDs Forbidden**: On OpenShift, Gateway API CRDs are managed by the Ingress Operator (this is normal)

5. **GPU Memory Issues**: Reduce `--max-model-len` or `--gpu-memory-utilization` in values.yaml
6. **Storage Issues**: Check PVC status and node storage availability
7. **Model Loading**: Verify HuggingFace token and network connectivity

### Debug Commands
```bash
# Check pod logs
oc logs <pod-name> -c vllm -n ${NAMESPACE} --tail=50

# Check GAIE scheduler logs
oc logs deployment/gaie-inference-scheduling-epp -n ${NAMESPACE} --tail=20

# Check GPU availability
oc describe nodes | grep -A 10 -B 5 "nvidia.com/gpu"

# Verify model download to PVC
oc exec <pod-name> -c vllm -n ${NAMESPACE} -- df -h /model-cache

# Check CRD installation
kubectl get crd | grep inference

# Monitor GPU operator initialization
oc get pods -n nvidia-gpu-operator

# Check deployment status with helmfile
cd inference-scheduling
helmfile status --namespace ${NAMESPACE}

# Test helmfile parsing
helmfile list --namespace ${NAMESPACE}
```

## Cleanup

### Automated Cleanup (Recommended)
```bash
# Navigate to inference-scheduling directory
cd inference-scheduling

# Clean up all components with confirmation
./cleanup.sh

# Force cleanup without prompts
./cleanup.sh --force

# Clean up and remove namespace
./cleanup.sh --remove-namespace
```

### Manual Cleanup
```bash
cd inference-scheduling

# Remove all components using helmfile
helmfile destroy --namespace ${NAMESPACE}

# Remove PVC
oc delete pvc llama-model-storage -n ${NAMESPACE}

# Remove HTTPRoute
oc delete httproute llm-d-inference-scheduling -n ${NAMESPACE}
```

## Directory Structure

```
llm-d-wlp-inference-scheduler/
├── README.md                    # This file - complete deployment guide
└── inference-scheduling/       # Main deployment directory (helmfile-based)
    ├── deploy-helmfile.sh      # Automated helmfile deployment script
    ├── test.sh                 # Testing and validation script
    ├── cleanup.sh              # Resource cleanup script
    ├── pvc.yaml                # Persistent Volume Claim for model storage
    ├── helmfile.yaml.gotmpl   # Main helmfile configuration
    ├── httproute.yaml          # HTTPRoute for inference routing
    ├── gateway-configurations/
    │   └── istio.yaml          # Istio gateway configuration
    ├── gaie-inference-scheduling/
    │   └── values.yaml         # GAIE configuration with EPP scorer options
    └── ms-inference-scheduling/
        ├── values.yaml         # Model service configuration (Qwen3-32B with PVC)
        └── values_tpu.yaml     # TPU-specific configuration
```

## Architecture

This deployment creates three main components:

1. **Infrastructure (llm-d-infra)**: Istio Gateway for external traffic routing
2. **GAIE (Gateway API Inference Extension)**: Precise prefix-cache-aware intelligent scheduling
3. **Model Service (llm-d-modelservice)**: vLLM instances with Qwen3-32B and multi-GPU support

Benefits:
- **Infrastructure-as-Code**: Declarative deployment with helmfile
- **Advanced Scheduling**: Precise prefix-cache-aware routing with real-time KV cache tracking
- **Multi-GPU Optimization**: Tensor parallelism (TP=2) across 4x L40S GPUs
- **Intelligent Load Balancing**: Multi-factor scoring (cache + utilization + queue depth)
- **Persistent Storage**: Models persist across pod restarts with PVC
- **Production Monitoring**: PodMonitor integration for Prometheus metrics
- **Scalable Architecture**: Easy horizontal scaling of inference workers

## Available Scripts

This well-lit path includes several automation scripts to simplify deployment and management:

### `inference-scheduling/deploy-helmfile.sh` - Automated Helmfile Deployment
- **Purpose**: Deploys the complete inference scheduling stack using helmfile
- **Features**: Dependency checking, namespace creation, PVC setup, automated helmfile sync
- **Usage**: `cd inference-scheduling && ./deploy-helmfile.sh [OPTIONS]`
- **Options**: `--namespace`, `--environment`, `--release-postfix`, `--help`

### `inference-scheduling/test.sh` - Validation and Testing
- **Purpose**: Tests the deployed stack with health checks and inference requests
- **Features**: Port forwarding, API testing, performance testing
- **Usage**: `cd inference-scheduling && ./test.sh [OPTIONS]`
- **Options**: `--namespace`, `--model`, `--port`, `--perf`, `--help`

### `inference-scheduling/cleanup.sh` - Resource Cleanup
- **Purpose**: Removes all deployed components and resources
- **Features**: Confirmation prompts, selective cleanup, namespace removal
- **Usage**: `cd inference-scheduling && ./cleanup.sh [OPTIONS]`
- **Options**: `--namespace`, `--force`, `--remove-namespace`, `--help`

### Quick Start Commands
```bash
# Complete deployment and testing workflow
export HF_TOKEN=your_token_here
export NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}

cd inference-scheduling
./deploy-helmfile.sh          # Deploy infrastructure
./test.sh                     # Test deployment
./test.sh --perf              # Run performance tests
./cleanup.sh                  # Clean up when done
``` 