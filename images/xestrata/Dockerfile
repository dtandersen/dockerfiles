# XeStrata runtime from upstream's prebuilt contrib .deb.
# No compile; setup.py finds the engine already built and only fetches
# the model on first start. Text-only by default (XESTRATA_VISION=no).

ARG UBUNTU_RELEASE=26.04
# Upstream tag, e.g. xe0.2.2-1. The .deb carries the Debian version
# (0.2.2-1), resolved via the release SHA256SUMS.
ARG XESTRATA_REF=xe0.2.2-1
# Package variant. cuda12.4 keeps Pascal/Volta (sm_60/61/70); CUDA 13 drops them.
ARG XESTRATA_VARIANT=contrib-cuda13.1

FROM ubuntu:${UBUNTU_RELEASE}
ARG XESTRATA_REF
ARG XESTRATA_VARIANT
ENV DEBIAN_FRONTEND=noninteractive
# oneMKL segfault 2026-10-14; 0 retries oneMKL/cuBLAS.
ENV STRATA_NO_BLAS=1
# MTP verify segfault 2026-10-14; 7 is upstream default.
ENV STRATA_ROUTE_TAIL_SKIP=0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && cd /tmp \
    && curl -fsSLO "https://github.com/MistVVK/XeStrata/releases/download/${XESTRATA_REF}/SHA256SUMS" \
    && DEB="$(grep -o "xestrata-${XESTRATA_VARIANT}_[^ ]*_amd64\\.deb" SHA256SUMS | head -n 1)" \
    && test -n "${DEB}" \
    && echo "installing ${DEB} for ${XESTRATA_REF}" \
    && curl -fsSLO "https://github.com/MistVVK/XeStrata/releases/download/${XESTRATA_REF}/${DEB}" \
    && grep -F " ${DEB}" SHA256SUMS | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends "./${DEB}" mesa-vulkan-drivers \
      libze1 libigc2 libigdfcl2 intel-opencl-icd ocl-icd-libopencl1 \
    && rm -f "./${DEB}" SHA256SUMS \
    && rm -rf /var/lib/apt/lists/* \
    && command -v xestrata

# Pinned Intel userspace: Ubuntu 26.04's compute-runtime has a device-memory
# bug and IGC 2.27-2.30 miscompiles on Battlemage.
ARG INTEL_CR=26.35.39758.10
ARG INTEL_IGC=2.41.5
ARG INTEL_IGC_BUILD=22716
ARG INTEL_GMMLIB=22.10.0
RUN cd /tmp \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/libze-intel-gpu1_${INTEL_CR}-0_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/intel-ocloc_${INTEL_CR}-0_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/libigdgmm12_${INTEL_GMMLIB}_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/intel-graphics-compiler/releases/download/v${INTEL_IGC}/intel-igc-core-2_${INTEL_IGC}+${INTEL_IGC_BUILD}_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/intel-graphics-compiler/releases/download/v${INTEL_IGC}/intel-igc-opencl-2_${INTEL_IGC}+${INTEL_IGC_BUILD}_amd64.deb" \
    && dpkg -i ./*.deb && apt-get install -y -f --no-install-recommends \
    && rm -f ./*.deb \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig -p | grep -q libze_intel_gpu

# Sanity check: PACKAGED layout, contrib engine, bundled SYCL 9, both
# vision encoders; only vendor libs (cuBLAS/oneMKL/ROCm) may be missing.
RUN ENGINE_BUILD="$(dpkg -L "xestrata-${XESTRATA_VARIANT}" 2>/dev/null | grep '/xestrata/engine/BUILD.json$' | head -n 1)" \
    && test -n "${ENGINE_BUILD}" \
    && echo "engine BUILD.json: ${ENGINE_BUILD}" \
    && test -f /usr/share/xestrata/setup.py \
    && test -f /usr/share/xestrata/PACKAGED \
    && ENGINE_DIR="$(dirname "${ENGINE_BUILD}")" \
    && test -x "${ENGINE_DIR}/strata" \
    && test -x "${ENGINE_DIR}/strata-vision-cpu" \
    && test -x "${ENGINE_DIR}/strata-vision-vulkan" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libsycl.so.9* 2>/dev/null)" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libonemath_blas_mklgpu.so* 2>/dev/null)" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libonemath_blas_cublas.so* 2>/dev/null)" \
    && /usr/bin/python3 -c 'import json, sys; build = json.load(open(sys.argv[1], encoding="utf-8")); assert build.get("license") == "contrib", build; assert build.get("source") == "package", build; print("engine:", build.get("package"), build.get("version"), build.get("license"))' "${ENGINE_BUILD}" \
    && (LD_LIBRARY_PATH="${ENGINE_DIR}/lib" ldd "${ENGINE_DIR}/strata" | grep 'not found' | grep -v -E 'libcublas|libmkl|libamdhip|librocblas|libhipblas' || true) \
    && ! (LD_LIBRARY_PATH="${ENGINE_DIR}/lib" ldd "${ENGINE_DIR}/strata" | grep 'not found' | grep -v -E 'libcublas|libmkl|libamdhip|librocblas|libhipblas')

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data", "/config"]
EXPOSE 8095
ENTRYPOINT ["/entrypoint.sh"]
