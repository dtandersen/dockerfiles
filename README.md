# Dockerfiles

My collection of container images and Helm charts.

Each image folder under `images/` has a `Dockerfile` and a README. Each chart
folder under `charts/` has a `Chart.yaml` and values, and is published to the
chart index by CI.

## Images

- [images/xestrata](images/xestrata/) — XeStrata AI chat on Intel GPUs (upstream .deb).
- [images/xestrata-llvm](images/xestrata-llvm/) — XeStrata AI chat on Intel GPUs (source build with intel/llvm --contrib).
- [images/forgejo-runner](images/forgejo-runner/) — Forgejo Actions runner that stays up as a daemon.
- [images/hl2270dw-ipp-bridge](images/hl2270dw-ipp-bridge/) — CUPS IPP-Everywhere bridge for Brother HL-2270DW (Windows Protected Print).
- [images/valheim](images/valheim/) — Valheim dedicated server, installed and updated with SteamCMD.
- [images/stationeers](images/stationeers/) — Stationeers dedicated server, installed and updated with SteamCMD.

Build one from the repo root, for example with
`docker build -t xestrata ./images/xestrata`.

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
no manual `.tgz` is committed. Images are built by the per-image workflows in
[.github/workflows](.github/workflows) and pushed to ghcr.io.

## Tags

Two tag namespaces, deliberately disjoint — a tag push ignores a workflow's
`paths:` filter, so a bare `0.5.0` would otherwise build every image here.

- **Image release:** `<image>-v<version>`, e.g. `xestrata-vxe0.2.2-1` or
  `forgejo-runner-v13.1.0`. Builds and pushes image tag `<version>`
  (`xe0.2.2-1`, `13.1.0`), which is what a chart's `appVersion` /
  `image.tag` should pin.
- **Chart release:** `<chart>-<version>`, e.g. `xestrata-0.1.1`, created by
  chart-releaser from `Chart.yaml` — never pushed by hand.

Branch pushes publish the branch name (`main`), except for an image a running
deployment pins by tag (`valheim`, `stationeers`): those publish only from a
release tag, and a branch push just builds them as a check.
