# BiomiX Docker Integration

This repository contains the Dockerfiles and build tooling to package BiomiX as a set of container images published to the GitHub Container Registry (GHCR).

> **What is a container image?** A container image is a self-contained, portable package that includes all the software and dependencies needed to run an application. Anyone with Docker installed can pull and run an image without installing anything else.

---

## Images

| Image | Description |
|---|---|
| `biomix-base` | Shared foundation — R 4.5.2, Bioconductor 3.21, Python venv, BiomiX source. All other images build on top of this one. |
| `biomix-transcriptomics` | Adds DESeq2, edgeR, limma, enrichR. |
| `biomix-methylomics` | Adds ChAMP and related packages. |
| `biomix-mofa` | Adds MOFA2, DESeq2, reticulate. |
| `biomix-metabolomics` | Adds MSnbase, QFeatures, Spectra and metabolomics toolchain. |
| `biomix-gui` | Adds Shiny frontend; exposes a web UI on port 3838. |

All images are published under the `ghcr.io/biomix-consortium` namespace.

---

## Building images locally

Local builds target the current machine's architecture only (`linux/amd64`) and do **not** push anything. They are useful for development and testing.

```bash
# Build the base image first — required by all other images.
make IMG_biomix_base

# Build individual analysis images (each depends on biomix-base).
make IMG_biomix_transcriptomics
make IMG_biomix_methylomics
make IMG_biomix_mofa
make IMG_biomix_metabolomics
make IMG_biomix_gui
```

---

## Pushing images to GHCR

Pushing builds multi-platform images (`linux/amd64` and `linux/arm64`) and publishes them to `ghcr.io/biomix-consortium`.

### Authenticate first

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u <your-github-username> --password-stdin
```

You need a GitHub personal access token with the `write:packages` scope. See [GitHub docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) for details.

### Push individual images

```bash
# Always push the base image before any child images.
make push_biomix_base

make push_biomix_transcriptomics
make push_biomix_methylomics
make push_biomix_mofa
make push_biomix_metabolomics
make push_biomix_gui
```

### Push all images at once

```bash
make push_all
```

---

## Pulling images

```bash
docker pull ghcr.io/biomix-consortium/biomix-base:latest
docker pull ghcr.io/biomix-consortium/biomix-transcriptomics:latest
docker pull ghcr.io/biomix-consortium/biomix-methylomics:latest
docker pull ghcr.io/biomix-consortium/biomix-mofa:latest
docker pull ghcr.io/biomix-consortium/biomix-metabolomics:latest
docker pull ghcr.io/biomix-consortium/biomix-gui:latest
```

If the repository is private you will need to authenticate (see above) before pulling.

---

## Running the GUI image

The `biomix-gui` image runs a Shiny web application that listens on port **3838** inside the container.

> **What is port mapping?** A container runs in an isolated environment. To access a service running inside it from your browser, you must forward a port on your machine to the container's port using the `-p` flag.

```bash
docker run --rm -p 3838:3838 ghcr.io/biomix-consortium/biomix-gui:latest
```

Then open `http://localhost:3838` in your browser.

To use a different local port (e.g. 8080):

```bash
docker run --rm -p 8080:3838 ghcr.io/biomix-consortium/biomix-gui:latest
```

Then open `http://localhost:8080`.

---

## Running a script inside an analysis image

Analysis images are designed to run individual BiomiX R scripts non-interactively. The general pattern is:

```
docker run --rm \
  -v <host-data-dir>:<container-data-dir> \
  -w <working-directory-inside-container> \
  <image> \
  Rscript <path-to-script>
```

> **What does this mean?**
> - `--rm` — remove the container automatically when it exits.
> - `-v src:dst` — mount a directory from your machine into the container so the script can read inputs and write outputs back to disk.
> - `-w` — set the working directory inside the container (the directory the script will see as its current location).
> - Everything after the image name is the command to run.

**Example — run `Biomix_DGE_GENES_LIMMA.r` against a local workspace:**

```bash
docker run --rm \
  -v /path/to/my/biomix_workspace:/opt/biomix/shared \
  -w /opt/biomix/BiomiX2.5 \
  ghcr.io/biomix-consortium/biomix-transcriptomics:latest \
  Rscript Transcriptomics/Biomix_DGE_GENES_LIMMA.r
```

`/path/to/my/biomix_workspace` should be a local directory that follows the BiomiX2.5 directory structure (containing `COMBINED_COMMANDS.json`, `Transcriptomics/INPUT/`, etc.). The mount replaces the copy of BiomiX2.5 that was baked into the image, so the script operates on your data while using the image's pre-installed R packages.
