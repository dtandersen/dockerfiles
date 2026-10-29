# Dockerfiles

My collection of Dockerfiles.

Each folder is one image with its own `Dockerfile` and README.

- [xestrata](xestrata/) — XeStrata AI chat on Intel GPUs (upstream .deb).
- [xestrata-llvm](xestrata-llvm/) — XeStrata AI chat on Intel GPUs (source build with intel/llvm --contrib).
- [forgejo-runner](forgejo-runner/) — Forgejo Actions runner that stays up as a daemon.
- [hl2270dw-ipp-bridge](hl2270dw-ipp-bridge/) — CUPS IPP-Everywhere bridge for Brother HL-2270DW (Windows Protected Print).

Build one, for example, with `docker build -t xestrata ./xestrata`.
