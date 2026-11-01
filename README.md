# Dockerfiles

My collection of container images and Helm charts.

Each image folder has a `Dockerfile` and a README. Each chart folder under
`charts/` has a `Chart.yaml` and values, and is published to the chart index
by CI.

## Images

- [xestrata](xestrata/) — XeStrata AI chat on Intel GPUs (upstream .deb).
- [xestrata-llvm](xestrata-llvm/) — XeStrata AI chat on Intel GPUs (source build with intel/llvm --contrib).
- [forgejo-runner](forgejo-runner/) — Forgejo Actions runner that stays up as a daemon.
- [hl2270dw-ipp-bridge](hl2270dw-ipp-bridge/) — CUPS IPP-Everywhere bridge for Brother HL-2270DW (Windows Protected Print).

Build one, for example, with `docker build -t xestrata ./xestrata`.

## Charts

- [charts/hl2270dw-ipp-bridge](charts/hl2270dw-ipp-bridge/) — IPP bridge deployment.
- [charts/netbird](charts/netbird/) — NetBird (submodule: dtandersen/helm-netbird, `homelab` branch).
- [charts/remote-pi-relay](charts/remote-pi-relay/) — pi remote relay.
- [charts/restic-rest-server](charts/restic-rest-server/) — restic REST server.
- [charts/valheim](charts/valheim/) — Valheim dedicated server.
- [charts/vllm](charts/vllm/) — vLLM OpenAI-compatible server.
- [charts/vllm-xe](charts/vllm-xe/) — vLLM on Intel GPUs.
- [charts/xestrata](charts/xestrata/) — XeStrata AI chat.

```
helm repo add dtandersen https://dtandersen.github.io/dockerfiles
helm search repo dtandersen
```

Charts are released by [.github/workflows/chart.yaml](.github/workflows/chart.yaml)
to the `gh-pages` branch whenever something under `charts/` lands on `main`;
no manual `.tgz` is committed. Images are built by the per-folder workflows
in [.github/workflows](.github/workflows) and pushed to ghcr.io.
