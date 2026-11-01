# xestrata

Helm chart for deploying [XeStrata](https://github.com/MistVVK/XeStrata) with
its OpenAI-compatible API. It is built on the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

XeStrata runs Qwen3.8-Flash-Next (125B MoE) on a single Intel Arc, AMD
Radeon, or NVIDIA GPU by keeping hot experts in VRAM and the full expert set
in host RAM. The chart is modeled on the `llama-intel` chart: one replica,
`Recreate` strategy, pinned to the B70 node, with node-local model storage.

## Image

Upstream publishes `.deb`/`.rpm` packages only — there is **no upstream
container image**. The image lives in the dockerfiles repo at `xestrata/`
(`Dockerfile` + `entrypoint.sh`): Ubuntu 26.04 with upstream's prebuilt
`contrib` package, checksum-verified against the release `SHA256SUMS`. There is
no compile step, so `setup.py` finds the engine already built and the pod's
first start only downloads the model (60–110 GB) and writes its config.

```text
ghcr.io/dtandersen/xestrata:main
```

The build workflow tags by branch (`main`) and commit SHA; upstream releases
are selected by the Dockerfile `XESTRATA_REF`/`XESTRATA_VARIANT` build args,
not by image tag. `appVersion` in `Chart.yaml` tracks `XESTRATA_REF`; the
default `image.tag` tracks the branch.

Intel userspace is pinned in the image (compute-runtime 26.35, IGC 2.41.5):
Ubuntu 26.04's compute-runtime has a device-memory bug and IGC 2.27–2.30
miscompile on Battlemage. The server starts text-only (`xestrata.vision: "no"`);
enabling vision needs an encoder on the GPU and costs about 0.9 GB.

## Values

The model is configured under `xestrata`:

```yaml
xestrata:
  family: ""      # "" (original), coder, swift, unsloth, ornith, llmjp
  model: IQ2_XS   # IQ2_XS fits ~48 GB RAM; IQ3_S needs ~64 GB
  contextSize: 32768
  vision: "no"
  dataDir: /data      # must match persistence.data.mountPath
  configDir: /config  # must match persistence.config.mountPath
  apiKey: ""      # optional; empty leaves the server unauthenticated
```

`model` and `contextSize` are setup-time only: changing them means deleting the
generated `config/xestrata/xestrata-*.json`, which otherwise pins the old
setup. The server always listens on container port `8095` — there is no port
override — and the Service maps port `80` to it (`/v1` is the OpenAI-compatible
base URL, `/health` is the probe endpoint). Model files live in the `data`
volume (`/data`, default hostPath `/var/cache/xestrata/data`) and settings in
the `config` volume (`/config`). The first start downloads 60-110 GB, so the
startup probe allows ~2 hours before failing.

GPU, memory, and placement defaults target the B70 on `kube-2`:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 32Gi
    gpu.intel.com/xe: 1
  limits:
    memory: 32Gi
    gpu.intel.com/xe: 1

podOptions:
  nodeSelector:
    kubernetes.io/hostname: kube-2
```

The memory request must cover the weights — below that the engine aborts with a
RAM/VRAM shortfall after loading. Do not schedule alongside `vllm-qwen38` or
`llama-intel` — all three want the same single B70. All other values are
supplied by the TrueCharts common chart (see its
[documentation](https://truecharts.org/common/) for `persistence`, `service`,
`ingress`, `certificate`, `extraTpl`, and security contexts).

## Helmfile

The chart is intended to be configured through Helmfile values, following the
`llama-intel` pattern (TLS certificate, ReferenceGrant, and HTTPRoute in the
release values, disabled sibling release while testing):

```yaml
releases:
  - name: xestrata
    chart: ../charts/charts/xestrata
    namespace: xestrata
    values:
      - releases/xestrata/values.yaml
```

## Upstream

- XeStrata: <https://github.com/MistVVK/XeStrata>
- Upstream Strata: <https://github.com/Niko1221/Strata>
- Model quants: <https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF>
- TrueCharts common: <https://truecharts.org/common/>
