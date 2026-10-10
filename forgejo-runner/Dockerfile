# Daemon-default entrypoint for the Forgejo runner image.
#
# gitea-charts/actions provides no container command override; it relies on
# the Gitea image's entrypoint script, while the stock Forgejo image's CMD is
# the bare binary (prints help and exits, restart-looping the Pod). This
# wrapper keeps the upstream ENTRYPOINT (dumb-init) and only supplies the
# daemon CMD against the chart-mounted config path.
#
# Rebuild tracking upstream (same tag both sides):
#   docker build -t ghcr.io/dtandersen/forgejo-runner:<tag> .
#   docker push ghcr.io/dtandersen/forgejo-runner:<tag>
# then point statefulset.runner.fullOverride in the helmfile
# releases/forgejo-runner-dind/values.yaml at the new tag.
FROM data.forgejo.org/forgejo/runner:13.1.0
CMD ["/bin/forgejo-runner", "--config", "/runner/config.yaml", "daemon"]
