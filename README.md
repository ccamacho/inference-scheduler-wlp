# LLM-D Well-Lit Path: Inference Scheduling Deployment

> **📁 All deployment files and scripts are in the [`inference-scheduling/`](./inference-scheduling/) directory. Start there for deployment.**

## 🚀 Quick Start - Corrected Working Deployment

This well-lit path provides a streamlined helmfile-based approach to deploying intelligent inference
scheduling with LLM-D. All deployment files and scripts are located in the `inference-scheduling/` directory.

**✅ Verified Working Setup (Updated September 16, 2025):**
- **Model**: [meta-llama/Llama-3.1-8B-Instruct](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct) (8B parameters)
- **Image**: ghcr.io/llm-d/llm-d-dev:pr-170 (dev build with latest features)
- **Hardware**: 4x GPUs (single GPU per replica)
- **Configuration**: 4 replicas × TP=1 (single GPU per replica)
- **Storage**: 50Gi (optimized for 8B model)
- **Gateway**: Upstream Istio with Gateway API Inference Extension support
- **Routing**: HTTPRoute → Gateway → InferencePool (GAIE) → Model Pods

**🔧 Critical Success Factors (Updated):**
- **Upstream Istio**: Required for Gateway API Inference Extension support
- **Chart Version Alignment**: v1.3.0 (infra) + v0.2.7 (modelservice) for compatibility
- **Manual HTTPRoute Application**: Required step from newer deployment guide
- **Gateway API CRDs**: Installed via install-gateway-provider-dependencies.sh
- **Service Type Configuration**: LoadBalancer for proper gateway functionality

## Environment Setup

```bash
# Export required environment variables
export KUBECONFIG=~/.kube/config
export NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}
export HF_TOKEN=$(cat ~/.keys/hf.key)
```

## Prerequisites (Updated)

### 1. Install Gateway Provider Dependencies (CRITICAL)
```bash
# Navigate to gateway provider directory
cd ./llm-d/guides/prereq/gateway-provider

# Install Gateway API and GAIE CRDs
./install-gateway-provider-dependencies.sh

# Note: On OpenShift, Gateway API CRDs are managed by Ingress Operator
# GAIE CRDs will be installed successfully
```

### 2. Remove OpenShift Service Mesh (If Present)
```bash
# OpenShift Service Mesh lacks Gateway API Inference Extension support
# Remove it to install upstream Istio

# Remove namespace from ServiceMesh (if added)
oc delete servicemeshmember default -n llm-d-inference-scheduling || true

# Remove ServiceMesh Control Plane
oc delete servicemeshcontrolplane data-science-smcp -n istio-system || true

# Wait for cleanup
sleep 30 && oc get pods -n istio-system
```

### 3. Install Upstream Istio with Gateway API Support
```bash
# Stay in gateway provider directory
cd ./llm-d/guides/prereq/gateway-provider

# Patch Istio CRDs for Helm ownership (required on OpenShift)
for crd in $(oc get crd | grep istio.io | awk '{print $1}'); do
  oc patch crd $crd --type='merge' -p='{"metadata":{"labels":{"app.kubernetes.io/managed-by":"Helm"},"annotations":{"meta.helm.sh/release-name":"istio-base","meta.helm.sh/release-namespace":"istio-system"}}}'
done

# Install upstream Istio with Gateway API Inference Extension
helmfile -f istio.helmfile.yaml sync

# Verify installation
oc get pods -n istio-system
oc wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=120s
```

### 4. Create Namespace and HuggingFace Token Secret
```bash
# Create namespace
oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -

# Create HuggingFace token secret
oc create secret generic llm-d-hf-token \
  --from-literal=HF_TOKEN=${HF_TOKEN} \
  -n ${NAMESPACE}
```

## Deployment (Updated Process)

### Helmfile Deployment with Corrected Configuration

Navigate to the `inference-scheduling` directory and deploy:

```bash
cd inference-scheduling

# Deploy with corrected chart versions and configuration
export NAMESPACE=llm-d-inference-scheduling
helmfile sync --namespace ${NAMESPACE}

# CRITICAL: Apply HTTPRoute manually (required by newer guide)
oc apply -f httproute.yaml
```

**Note**: The helmfile now uses:
- **llm-d-infra v1.3.0** (downgraded for compatibility)
- **llm-d-modelservice v0.2.7** (downgraded for schema compatibility)  
- **ghcr.io/llm-d/llm-d-dev:pr-170** (dev build with latest features)

### Deployment Timeline (Updated)

**Expected deployment phases:**
1. **Gateway Provider Setup (5-10min)**: Istio installation and CRD setup
2. **Infrastructure (30-60s)**: Gateway and networking components
3. **GAIE Scheduler (30-60s)**: Intelligent inference routing
4. **Model Service (5-15min)**: vLLM pods with model download

**Gateway Initialization**: The gateway will show "PROGRAMMED: True" when ready, and the gateway service will be created automatically.

## Verification and Testing (Reference Guide Compliant)

### Check Deployment Status
```bash
echo "=== Helm Releases ==="
helm list -n ${NAMESPACE}

echo "=== Pod Status ==="
oc get pods -n ${NAMESPACE}

echo "=== Gateway Status ==="
oc get gateway,httproute,inferencepool -n ${NAMESPACE}

echo "=== Services ==="
oc get svc -n ${NAMESPACE}

# Verify gateway service exists
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Gateway Service Found: $GATEWAY_SVC"
```

### Test Inference (Following getting-started-inferencing.md)

```bash
# Set up environment variables
export NAMESPACE=llm-d-inference-scheduling
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)

# Port forward to gateway (reference guide approach)
export ENDPOINT="http://localhost:8000"
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &

# Test /v1/models endpoint
curl -s ${ENDPOINT}/v1/models -H "Content-Type: application/json" | jq

# Test /v1/completions endpoint
curl -X POST ${ENDPOINT}/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "prompt": "How are you today?",
    "max_tokens": 10
  }' | jq

# Test /v1/chat/completions endpoint
curl -X POST ${ENDPOINT}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "messages": [
      {
        "role": "user", 
        "content": "Hello! What is machine learning?"
      }
    ],
    "max_tokens": 50,
    "temperature": 0.7
  }' | jq

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

## Troubleshooting (Updated)

### Critical Gateway Issues (RESOLVED)

1. **Gateway shows "Unknown" status**: 
   - **Root Cause**: OpenShift Service Mesh lacks Gateway API Inference Extension support
   - **Solution**: Install upstream Istio with `SUPPORT_GATEWAY_API_INFERENCE_EXTENSION=true`
   ```bash
   # Remove OpenShift Service Mesh and install upstream Istio
   cd h100-dagray2/llm-d/guides/prereq/gateway-provider
   helmfile -f istio.helmfile.yaml sync
   ```

2. **Gateway service not created**:
   - **Root Cause**: Missing Gateway API controller or incorrect Istio version
   - **Solution**: Ensure upstream Istio is installed and gateway shows "PROGRAMMED: True"
   ```bash
   oc get gateway -n ${NAMESPACE}  # Should show PROGRAMMED: True
   oc get svc -n ${NAMESPACE} | grep gateway  # Should show gateway service
   ```

3. **Schema validation errors**:
   - **Root Cause**: Chart version incompatibility (v0.2.9 has stricter schema)
   - **Solution**: Use compatible chart versions (v1.3.0 + v0.2.7)
   ```bash
   # Ensure helmfile.yaml.gotmpl has correct versions:
   # llm-d-infra: v1.3.0
   # llm-d-modelservice: v0.2.7
   ```

### Common Issues

1. **Missing CRDs**: Use the gateway provider dependencies script:
   ```bash
   cd h100-dagray2/llm-d/guides/prereq/gateway-provider
   ./install-gateway-provider-dependencies.sh
   ```

2. **GAIE Pod CrashLoopBackOff**: Usually caused by missing InferenceModel CRD. Install CRDs and restart:
   ```bash
   oc rollout restart deployment gaie-inference-scheduling-epp -n ${NAMESPACE}
   ```

3. **Model Compatibility Issues**: 
   - **Apertus models**: Not supported by current vLLM version (use Llama or Qwen models)
   - **Large models**: Ensure sufficient GPU memory and storage
   ```bash
   # Check model compatibility
   oc logs <model-pod> -c vllm -n ${NAMESPACE} --tail=20
   ```

4. **Pods Pending - Insufficient GPU**: Check GPU device plugin status:
   ```bash
   # Check GPU operator pods
   oc get pods -A | grep -i gpu
   
   # Check node GPU capacity (should show nvidia.com/gpu)
   oc describe node <gpu-node-name> | grep -A10 "Capacity:"
   
   # Wait for GPU device plugin initialization (can take 5-10 minutes)
   oc get pods -n nvidia-gpu-operator | grep device-plugin
   ```

5. **HTTPRoute not working**: Apply manually after helmfile deployment:
   ```bash
   oc apply -f httproute.yaml
   ```

6. **GPU Memory Issues**: Reduce model parameters or GPU utilization in values.yaml
7. **Storage Issues**: Check PVC status and node storage availability  
8. **Model Loading**: Verify HuggingFace token and network connectivity

### Debug Commands (Updated)
```bash
# Check gateway status (CRITICAL)
oc get gateway -n ${NAMESPACE}  # Should show PROGRAMMED: True
oc get svc -n ${NAMESPACE} | grep gateway  # Should show gateway service

# Verify complete routing stack
oc get gateway,httproute,inferencepool -n ${NAMESPACE}

# Check pod logs
oc logs <pod-name> -c vllm -n ${NAMESPACE} --tail=50

# Check GAIE scheduler logs
oc logs deployment/gaie-inference-scheduling-epp -n ${NAMESPACE} --tail=20

# Check Istio controller logs
oc logs deployment/istiod -n istio-system --tail=20

# Test gateway service discovery (reference guide approach)
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Gateway Service Found: $GATEWAY_SVC"

# Verify Gateway API CRDs
oc get crd | grep -E "(gateway|inference)"

# Check Istio installation
oc get pods -n istio-system
helm list -n istio-system

# Test inference endpoints through gateway
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &
curl -s http://localhost:8000/v1/models | jq '.data[].id'
kill %1

# Check deployment status with helmfile
cd inference-scheduling
helmfile status --namespace ${NAMESPACE}
```

### Success Verification Checklist

✅ **Gateway Infrastructure Working:**
```bash
# Gateway should show PROGRAMMED: True
oc get gateway -n ${NAMESPACE}

# Gateway service should exist
oc get svc -n ${NAMESPACE} | grep "infra-inference-scheduling-inference-gateway-istio"

# Gateway pod should be running
oc get pods -n ${NAMESPACE} | grep "infra-inference-scheduling-inference-gateway-istio"
```

✅ **Reference Guide Compliance:**
```bash
# Service discovery should work
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Found: $GATEWAY_SVC"  # Should output the gateway service name

# All API endpoints should work through gateway
export ENDPOINT="http://localhost:8000"
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &
curl -s ${ENDPOINT}/v1/models | jq  # Should return model list
curl -X POST ${ENDPOINT}/v1/completions -H 'Content-Type: application/json' -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","prompt":"Test","max_tokens":5}' | jq
kill %1
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

## 🎯 Working Configuration Summary

**This deployment has been verified to work on OpenShift with the following key components:**

### **✅ Successful Architecture:**
```
Client → Istio Gateway → HTTPRoute → InferencePool (GAIE) → Model Pods
```

### **✅ Key Configuration Files:**
- `helmfile.yaml.gotmpl` - Chart versions: infra v1.3.0 + modelservice v0.2.7
- `ms-inference-scheduling/values.yaml` - Model: Llama-3.1-8B-Instruct + pr-170 image
- `gateway-configurations/istio.yaml` - LoadBalancer service type
- `httproute.yaml` - Manual application required

### **✅ Critical Success Factors:**
1. **Upstream Istio**: Required for Gateway API Inference Extension support
2. **Chart Version Alignment**: Specific versions required for compatibility
3. **Manual HTTPRoute**: Must be applied after helmfile deployment
4. **Gateway Service**: Creates `infra-inference-scheduling-inference-gateway-istio`

### **✅ Verification Commands:**
```bash
# Quick verification that everything is working
export NAMESPACE=llm-d-inference-scheduling

# Check gateway is programmed
oc get gateway -n ${NAMESPACE}  # PROGRAMMED: True

# Check all pods running
oc get pods -n ${NAMESPACE}  # All should be Running

# Test inference
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Gateway: $GATEWAY_SVC"  # Should find the service
```

### **🚀 Updated Quick Start Commands**
```bash
# Complete deployment and testing workflow (CORRECTED)
export HF_TOKEN=$(cat ~/.keys/hf.key)
export NAMESPACE=${NAMESPACE:-llm-d-inference-scheduling}

# 1. Install Gateway Provider Dependencies
cd h100-dagray2/llm-d/guides/prereq/gateway-provider
./install-gateway-provider-dependencies.sh

# 2. Install Upstream Istio (if OpenShift Service Mesh present)
helmfile -f istio.helmfile.yaml sync

# 3. Deploy LLM-D Stack
cd ../../inference-scheduler-wlp/inference-scheduling
helmfile sync --namespace ${NAMESPACE}
oc apply -f httproute.yaml

# 4. Test deployment (reference guide compliant)
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &
curl -s http://localhost:8000/v1/models | jq
kill %1

# 5. Clean up when done
./cleanup.sh
```

This configuration provides a **production-ready inference scheduling system** with intelligent routing, load balancing, and full Gateway API compliance following the reference documentation.

## 📚 Complete Working Configuration Documentation

### **✅ Verified Working Configuration Summary**

**Chart Versions (aligned with newer guide):**
- **llm-d-infra**: v1.3.0 
- **llm-d-modelservice**: v0.2.7
- **inferencepool**: v0.5.1

**Model Configuration:**
- **Model**: meta-llama/Llama-3.1-8B-Instruct (8B parameters)
- **Image**: ghcr.io/llm-d/llm-d-dev:pr-170 (dev build)
- **Replicas**: 4 (single GPU per replica)
- **Storage**: 50Gi

**Gateway Infrastructure:**
- **Gateway**: infra-inference-scheduling-inference-gateway (PROGRAMMED: True)
- **Service**: infra-inference-scheduling-inference-gateway-istio (ClusterIP)
- **HTTPRoute**: llm-d-inference-scheduling (working)
- **GAIE Scheduler**: gaie-inference-scheduling-epp (intelligent routing)

### **🔧 Critical Issues Resolved**

**1. ISTIO GATEWAY API SUPPORT:**
- **Problem**: OpenShift Service Mesh lacked Gateway API Inference Extension support
- **Solution**: Replaced with upstream Istio 1.28-alpha with `SUPPORT_GATEWAY_API_INFERENCE_EXTENSION=true`

**2. CHART VERSION COMPATIBILITY:**
- **Problem**: v0.2.9 modelservice chart had stricter schema validation
- **Solution**: Downgraded to v0.2.7 and restored `routing.modelName` property

**3. SERVICE TYPE CONFIGURATION:**
- **Problem**: Gateway configured as ClusterIP instead of expected LoadBalancer
- **Solution**: Updated `gateway-configurations/istio.yaml` with `service.type: LoadBalancer`

**4. MISSING GATEWAY PROVIDER DEPENDENCIES:**
- **Problem**: Missing Gateway API CRDs and GAIE CRDs
- **Solution**: Applied `install-gateway-provider-dependencies.sh`

**5. SERVICEMESH MEMBERSHIP:**
- **Problem**: Namespace not in ServiceMesh member roll
- **Solution**: Added ServiceMeshMember (later removed with ServiceMesh)

### **📋 Complete Deployment Command Reference**

```bash
# 1. Install Gateway Provider Dependencies
cd h100-dagray2/llm-d/guides/prereq/gateway-provider
./install-gateway-provider-dependencies.sh

# 2. Remove OpenShift Service Mesh (if present)
oc delete servicemeshmember default -n llm-d-inference-scheduling || true
oc delete servicemeshcontrolplane data-science-smcp -n istio-system || true

# 3. Patch Istio CRDs for Helm ownership
for crd in $(oc get crd | grep istio.io | awk '{print $1}'); do
  oc patch crd $crd --type='merge' -p='{"metadata":{"labels":{"app.kubernetes.io/managed-by":"Helm"},"annotations":{"meta.helm.sh/release-name":"istio-base","meta.helm.sh/release-namespace":"istio-system"}}}'
done

# 4. Install Upstream Istio with Gateway API Inference Extension
helmfile -f istio.helmfile.yaml sync

# 5. Deploy LLM-D Stack
cd ../../inference-scheduler-wlp/inference-scheduling
export NAMESPACE=llm-d-inference-scheduling
export HF_TOKEN=$(cat ~/.keys/hf.key)
helmfile sync --namespace ${NAMESPACE}

# 6. Apply HTTPRoute manually
oc apply -f httproute.yaml
```

### **🧪 Complete Testing Reference (getting-started-inferencing.md Compliant)**

```bash
# Service Discovery (as per getting-started-inferencing.md)
export NAMESPACE=llm-d-inference-scheduling
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Gateway Service: $GATEWAY_SVC"

# Port Forward to Gateway
export ENDPOINT="http://localhost:8000"
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &

# Test /v1/models endpoint
curl -s ${ENDPOINT}/v1/models -H "Content-Type: application/json" | jq

# Test /v1/completions endpoint
curl -X POST ${ENDPOINT}/v1/completions -H 'Content-Type: application/json' -d '{
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "prompt": "How are you today?",
  "max_tokens": 10
}' | jq

# Test /v1/chat/completions endpoint
curl -X POST ${ENDPOINT}/v1/chat/completions -H "Content-Type: application/json" -d '{
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "messages": [{"role": "user", "content": "Hello! What is machine learning?"}],
  "max_tokens": 50,
  "temperature": 0.7
}' | jq

# Stop port forward
kill %1
```

### **📊 Expected Resources After Successful Deployment**

**PODS:**
- `gaie-inference-scheduling-epp-*` (1/1 Running) - GAIE scheduler
- `infra-inference-scheduling-inference-gateway-istio-*` (1/1 Running) - Gateway pod
- `ms-inference-scheduling-llm-d-modelservice-decode-*` (2/2 Running) x4 - Model service pods

**SERVICES:**
- `gaie-inference-scheduling-epp` (ClusterIP 9002/9090) - GAIE scheduler
- `infra-inference-scheduling-inference-gateway-istio` (ClusterIP 15021/80) - Gateway service

**DEPLOYMENTS:**
- `gaie-inference-scheduling-epp` (1/1 Available)
- `infra-inference-scheduling-inference-gateway-istio` (1/1 Available)
- `ms-inference-scheduling-llm-d-modelservice-decode` (4/4 Available)

**GATEWAY API RESOURCES:**
- **Gateway**: infra-inference-scheduling-inference-gateway (PROGRAMMED: True)
- **HTTPRoute**: llm-d-inference-scheduling (attached to gateway)
- **InferencePool**: gaie-inference-scheduling (targeting model pods)

### **🔧 Key Configuration Files Documentation**

**1. helmfile.yaml.gotmpl:**
- llm-d-infra: v1.3.0 (downgraded for compatibility)
- llm-d-modelservice: v0.2.7 (downgraded for schema compatibility)
- Removed monitoring override for clean deployment

**2. ms-inference-scheduling/values.yaml:**
- Model: meta-llama/Llama-3.1-8B-Instruct (8B model)
- Image: ghcr.io/llm-d/llm-d-dev:pr-170 (dev build with latest features)
- Replicas: 4 (optimized for throughput)
- Args: Simplified to match newer guide (removed production optimizations)
- Added back routing.modelName for v0.2.7 compatibility

**3. gateway-configurations/istio.yaml:**
- Added service.type: LoadBalancer (required by getting-started guide)
- Kept destinationRule configuration for proper routing

**4. httproute.yaml:**
- Applied manually as required by newer guide
- Routes to InferencePool for intelligent scheduling

### **🧪 Benchmark Integration with Multiturn Support**

The benchmark job has been updated to use our working LLM-D service with [multiturn benchmarking support from PR #211](https://github.com/vllm-project/guidellm/pull/211/):

**Dockerfile Updates (`bench/Dockerfile`):**
```dockerfile
# Builds guidellm with multiturn support from PR #211
RUN git clone https://github.com/vllm-project/guidellm.git \
 && cd guidellm \
 && git fetch origin pull/211/head:feat/multiturn \
 && git checkout feat/multiturn \
 && echo "Building guidellm with multiturn support from PR #211..." \
 && python -m build --wheel --no-isolation
```

**Benchmark Job Updates (`bench/guidellm-job.yml`):**
- **Target**: `http://infra-inference-scheduling-inference-gateway-istio.llm-d-inference-scheduling.svc.cluster.local`
- **Model**: `meta-llama/Llama-3.1-8B-Instruct` (our working model)
- **Endpoint**: `/v1/chat/completions` (full chat interface)
- **Multiturn**: 3-turn conversations with 16 concurrent users
- **Duration**: 120 seconds for comprehensive testing
- **Tokens**: 256 prompt tokens, 256 output tokens per turn
- **Metrics**: Monitors `llm-d-inference-scheduling` namespace and Istio metrics

### **Running the Benchmark**

```bash
# Create benchmark namespace and secrets
oc create namespace bench
oc create secret generic hf-token-secret --from-literal=HF_TOKEN=${HF_TOKEN} -n bench

# Apply the benchmark job
oc apply -f bench/guidellm-job.yml

# Monitor benchmark progress
oc logs -f job/guidellm-benchmark -n bench -c benchmark

# Check results
oc logs job/guidellm-benchmark -n bench -c benchmark | grep -E "(Benchmark|Results|complete)"

# Get benchmark results
oc exec $(oc get pods -n bench -l job-name=guidellm-benchmark -o jsonpath='{.items[0].metadata.name}') -n bench -c sidecar -- ls -la /output
```

### **What the Benchmark Tests**

**1. Service Accessibility:**
- Verifies LLM-D service is reachable from within cluster
- Tests `/v1/models` endpoint for model availability
- Validates chat completions endpoint functionality

**2. Multiturn Conversations:**
- Tests 3-turn conversation flows (PR #211 feature)
- Measures conversation context handling
- Evaluates multi-exchange performance

**3. Gateway Performance:**
- Tests complete routing stack: Gateway → HTTPRoute → InferencePool → Model Pods
- Measures GAIE intelligent routing decisions
- Evaluates load balancing across 4 model replicas

**4. Production Metrics:**
- **GPU Utilization**: During actual inference workloads
- **Container Metrics**: CPU, memory, network for LLM-D namespace
- **Istio Metrics**: Request rates and latency through gateway
- **vLLM Metrics**: Model-specific performance data

This benchmark provides comprehensive testing of the complete LLM-D inference scheduling system with real workloads and the latest guidellm features.



### **🔍 Advanced Troubleshooting Guide**

**Gateway shows "Unknown" status:**
- Check if upstream Istio is installed with Gateway API support
- Verify `SUPPORT_GATEWAY_API_INFERENCE_EXTENSION=true` in istiod config
- Ensure namespace is not in OpenShift Service Mesh member roll

**Model pods in CrashLoopBackOff:**
- Check model compatibility with vLLM version (Apertus models not supported)
- Verify HF_TOKEN secret exists and is valid
- Check GPU availability and resource requests

**Schema validation errors:**
- Ensure chart versions are compatible (v1.3.0 + v0.2.7)
- Check for deprecated properties in values.yaml
- Verify routing.modelName exists for older chart versions

**Gateway service not created:**
- Verify Gateway API CRDs are installed
- Check if Gateway controller is processing resources
- Ensure proper service type configuration

**HTTPRoute not working:**
- Apply HTTPRoute manually after helmfile deployment
- Verify InferencePool exists and is ready
- Check gateway parentRef name matches actual gateway

### **✅ Quick Verification Commands**

```bash
# Check all components
export NAMESPACE=llm-d-inference-scheduling
helm list -n ${NAMESPACE}
oc get all -n ${NAMESPACE}
oc get gateway,httproute,inferencepool -n ${NAMESPACE}

# Verify gateway functionality
GATEWAY_SVC=$(oc get svc -n "${NAMESPACE}" -o yaml | yq '.items[] | select(.metadata.name | test(".*-inference-gateway(-.*)?$")).metadata.name' | head -n1)
echo "Gateway Service Found: $GATEWAY_SVC"

# Test inference endpoints
oc port-forward -n ${NAMESPACE} service/${GATEWAY_SVC} 8000:80 &
sleep 3
curl -s http://localhost:8000/v1/models | jq '.data[].id'
kill %1
``` 