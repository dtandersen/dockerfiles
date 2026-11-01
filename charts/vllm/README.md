# vllm

Helm chart for deploying [vLLM](https://vllm.ai) with the
OpenAI-compatible API. It is built on the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

The chart is intentionally minimal. The model, GPU resources, node selection,
storage backend, and backend-specific vLLM arguments should be supplied by the
consuming Helmfile.

## Values

The chart provides the vLLM image, command, health probes, service port, and a
writable cache volume. The model is configured under `vllm.model`:

```yaml
vllm:
  model: Qwen/Qwen3-4B
```

The default workload runs:

```text
vllm serve <vllm.model> --host 0.0.0.0 --port 8000
```

The service exposes port `80` and targets container port `8000`. The cache is
mounted at `/data` and is enabled by default. Override `persistence.hf-cache`
from Helmfile when using a different storage backend or an existing claim.

All other values are supplied by the TrueCharts common chart. See the [common
chart documentation](https://truecharts.org/common/) for options including
`resources`, `podOptions`, `persistence`, `service`, `ingress`, `hpa`, and
security contexts.

## Helmfile

The chart is intended to be configured through Helmfile values. For example:

```yaml
releases:
  - name: vllm
    chart: dtandersen/vllm
    namespace: vllm
    createNamespace: true
    values:
      - releases/vllm/values.yaml.gotmpl
```

A consuming values file can override the model, backend image, GPU resource,
node, and vLLM arguments:

```yaml
vllm:
  model: Qwen/Qwen3-4B

image:
  repository: vllm/vllm-openai
  tag: v0.27.1

podOptions:
  nodeSelector:
    kubernetes.io/hostname: gpu-1

resources:
  requests:
    nvidia.com/gpu: 1
  limits:
    nvidia.com/gpu: 1

workload:
  main:
    strategy: Recreate
    podSpec:
      containers:
        main:
          args:
            - serve
            - "{{ .Values.vllm.model }}"
            - --host
            - 0.0.0.0
            - --port
            - "8000"
```

For Intel XPU or another backend, override `image`, the device-plugin resource,
and the container `args`/`env` in the same way.

## Installation

Add the Helm repository and install the chart:

```console
helm repo add dtandersen https://dtandersen.github.io/dockerfiles
helm install vllm dtandersen/vllm \
  --namespace vllm \
  --create-namespace \
  --set vllm.model=Qwen/Qwen3-4B
```

The `common` dependency is bundled in the published chart package.

## Upstream

- vLLM: <https://github.com/vllm-project/vllm>
- Default image: <https://hub.docker.com/r/vllm/vllm-openai>
- TrueCharts common: <https://truecharts.org/common/>
