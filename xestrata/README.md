# xestrata

[xestrata](https://github.com/MistVVK/XeStrata) is an Intel-first, but not Intel only, port of [strata](https://github.com/Niko1221/Strata). The GPU code was rewritten from CUDA to SYCL/Level Zero.

It is made to run MoE models that are too large to fit in VRAM. The experts live in RAM and `xestrata` learns which ones are most used and swaps them into VRAM. It can also run the experts on the CPU.

## Volumes

- /data - model weights
- /config - configuration files
- /root/.cache - neo compiler cache

## Model

Put the model into /data.

Set the model name, e.g. `XESTRATA_MODEL=IQ3_S`, and it downloads `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` from Huggingface into `/data`.

`XESTRATA_FAMILY=qwen` is set by default for the Qwen 3.8 Flash Next family of models.

## Settings

Everything is an environment variable. Defaults work out of the box.

- XESTRATA_MODEL - which model to download (default IQ2_XS)
- XESTRATA_LICENSE - build mode matching the image (default free)
- XESTRATA_INTEL_LLVM - compiler path baked into the image (default /opt/xestrata/.tools/intel-llvm/install)

## Ports

The `xestrata` OpenAI compatible endpoint is on port 8095.


## Example

```sh
docker run -d --name xestrata --device /dev/dri \
  -p 8095:8095 \
  -v xestrata-data:/data -v xestrata-config:/config \
  -e XESTRATA_MODEL=IQ3_S \
  ghcr.io/dtandersen/xestrata:xe0.1.43.1
```

First start downloads the model (~84 GB) into the data volume, then
serves it. Chat at http://localhost:8095, or point any OpenAI-compatible
app at http://localhost:8095/v1.
