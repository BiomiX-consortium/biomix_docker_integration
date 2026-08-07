# BiomiX Docker Integration

This repository contains the Dockerfiles and build tooling to package BiomiX as a set of container images published to the GitHub Container Registry (GHCR).

> **What is a container image?** A container image is a self-contained, portable package that includes all the software and dependencies needed to run an application. Anyone with Docker installed can pull and run an image without installing anything else.

---

## Quick start (recommended for most users)

If you just want to **run BiomiX** and don't need to build or modify anything, download the launcher for your operating system from the [Releases page](../../releases):

- **Windows**: `BiomiX_Start.bat` + `BiomiX_Start.ps1` — download **both**, keep them in the same folder, double-click `BiomiX_Start.bat`.
- **macOS / Linux**: `BiomiX_Start.sh` — download it, then run `chmod +x BiomiX_Start.sh` once, and double-click it (or run `./BiomiX_Start.sh` from a terminal).

The launcher will:
1. Check that Docker Desktop is running (and try to start it for you if it isn't).
2. Show which BiomiX components are already downloaded, and let you pick which ones to download.
3. Let you choose a folder on your computer for input files and results.
4. Let you optionally enter an NCBI API key (speeds up literature-search steps — free at [ncbi.nlm.nih.gov/account/settings](https://www.ncbi.nlm.nih.gov/account/settings)).
5. Start BiomiX and open it in your browser automatically.

No command line, no Docker knowledge required. The sections below are for developers who want to build, modify, or run the images manually.

---

## Images

BiomiX is split across several images so that each analysis type only pulls the packages it actually needs.

| Image | Description |
|---|---|
| `biomix-base` | Shared foundation — R, Bioconductor, Python venv, BiomiX source. All other images build on top of this one. Never run directly. |
| `biomix-gui` | Shiny frontend; exposes a web UI on port 3838. Orchestrates the other images (see [Architecture](#architecture) below). |
| `biomix-transcriptomics` | Adds DESeq2, edgeR, limma, enrichR. |
| `biomix-metabolomics` | Adds MSnbase, QFeatures, Spectra, cmmr, metpath, and the metabolomics toolchain. |
| `biomix-methylomics` | Adds ChAMP and related packages. |
| `biomix-mofa-diablo` | Adds MOFA2, mixOmics (DIABLO), mofapy2 (Python), GGally, ggpubr. Handles both single-factor and automatic multi-factor MOFA runs, plus DIABLO integration. |
| `biomix-snf-nemo` | Adds SNFtool, NEMO, and the clustering/network-fusion toolchain (visNetwork, fpc, aricode, survival, survminer, etc.). |
| `biomix-interpretation` | Adds enrichR, metpath, litsearchr, rentrez and related packages for pathway interpretation, clinical correlation, and PubMed literature mining. |

All images are published under the `ghcr.io/biomix-consortium` namespace.

### Tags

- `:latest` — the stable, officially maintained set of images.
- `:V2` — the current development line described in this README (restructured for Docker-in-Docker orchestration; see below). Use this tag if you want the features described here.

---

## Architecture

Starting with `:V2`, `biomix-gui` doesn't run every analysis itself — it **orchestrates sibling containers** for the heavier, package-specific steps (transcriptomics, metabolomics, methylomics, MOFA/DIABLO, SNF/NEMO, interpretation). This keeps each image focused and avoids bloating the GUI image with every possible dependency.

To do this, `biomix-gui`:
- Has the Docker CLI installed.
- Needs the host's Docker socket mounted (`-v /var/run/docker.sock:/var/run/docker.sock`) so it can launch sibling containers on your machine's Docker engine.
- Needs to know the **host** path of your shared data folder (`BIOMIX_HOST_SHARED_PATH`), so it can pass the correct mount when launching those sibling containers — a path *inside* the GUI container isn't meaningful to the host's Docker engine.

All data — inputs, the run configuration, and results — lives in a single folder that you mount into `biomix-gui` (and that BiomiX in turn mounts into whichever sibling container it launches) as `/shared`.

---

## Building images locally

Local builds target the current machine's architecture only (`linux/amd64`) and do **not** push anything. They are useful for development and testing.

```bash
# Build the base image first — required by all other images.
make IMG_biomix_base

# Build individual images (each depends on biomix-base).
make IMG_biomix_gui
make IMG_biomix_transcriptomics
make IMG_biomix_metabolomics
make IMG_biomix_methylomics
make IMG_biomix_mofa_diablo
make IMG_biomix_snf_nemo
make IMG_biomix_interpretation

# Or build everything at once:
make IMG_all
```

> **Note on `arm64` (Apple Silicon Macs):** building `arm64` under QEMU emulation (e.g. on a Windows or Intel-based build machine) is unreliable for R/Bioconductor images — package compilation and binary resolution can fail in ways that don't reproduce on real hardware. `arm64` builds should be done natively, on an actual ARM64 machine, then merged with the `amd64` build into a single multi-architecture tag:
>
> ```bash
> # On amd64 hardware:
> docker buildx build --platform linux/amd64 -f docker/biomix_base.Dockerfile \
>   -t ghcr.io/biomix-consortium/biomix-base:V2-amd64 --push .
>
> # On real arm64 hardware (e.g. an Apple Silicon Mac):
> docker buildx build --platform linux/arm64 -f docker/biomix_base.Dockerfile \
>   -t ghcr.io/biomix-consortium/biomix-base:V2-arm64 --push .
>
> # From any machine, merge the two into one multi-arch tag:
> docker buildx imagetools create -t ghcr.io/biomix-consortium/biomix-base:V2 \
>   ghcr.io/biomix-consortium/biomix-base:V2-amd64 \
>   ghcr.io/biomix-consortium/biomix-base:V2-arm64
> ```

---

## Pushing images to GHCR

### Authenticate first

```bash
docker login ghcr.io -u <your-github-username>
```

Use a GitHub personal access token (classic) with the `write:packages` and `read:packages` scopes as the password — not your GitHub account password. See [GitHub docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) for details on creating one.

### Push individual images

```bash
# Always push the base image before any child images, and wait for it
# to finish before pushing images that depend on it.
make push_biomix_base

make push_biomix_gui
make push_biomix_transcriptomics
make push_biomix_metabolomics
make push_biomix_methylomics
make push_biomix_mofa_diablo
make push_biomix_snf_nemo
make push_biomix_interpretation
```

### Push all images at once

```bash
make push_all
```

Verify what's published at: `https://github.com/orgs/biomix-consortium/packages`

---

## Pulling images

```bash
docker pull ghcr.io/biomix-consortium/biomix-base:V2
docker pull ghcr.io/biomix-consortium/biomix-gui:V2
docker pull ghcr.io/biomix-consortium/biomix-transcriptomics:V2
docker pull ghcr.io/biomix-consortium/biomix-metabolomics:V2
docker pull ghcr.io/biomix-consortium/biomix-methylomics:V2
docker pull ghcr.io/biomix-consortium/biomix-mofa-diablo:V2
docker pull ghcr.io/biomix-consortium/biomix-snf-nemo:V2
docker pull ghcr.io/biomix-consortium/biomix-interpretation:V2
```

If the repository is private you will need to authenticate (see above) before pulling. You only need to pull the components relevant to the analyses you plan to run — `biomix-gui` is the only one that's always required.

---

## Running the GUI image manually

If you'd rather not use the launcher scripts, you can start BiomiX by hand:

```bash
docker run -p 3838:3838 --rm -it \
  -e BIOMIX_HOST_SHARED_PATH="/path/to/your/shared/folder" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "/path/to/your/shared/folder:/shared" \
  ghcr.io/biomix-consortium/biomix-gui:V2
```

Then open `http://localhost:3838` in your browser.

> **What is port mapping?** A container runs in an isolated environment. To access a service running inside it from your browser, you must forward a port on your machine to the container's port using the `-p` flag.

### About the flags

| Flag | Why it's needed |
|---|---|
| `-e BIOMIX_HOST_SHARED_PATH=...` | Tells BiomiX the **host** path of your shared folder, so it can correctly mount it into any sibling container it launches (see [Architecture](#architecture)). Must match the source side of the `-v .../shared:/shared` mount below. |
| `-v /var/run/docker.sock:/var/run/docker.sock` | Lets the GUI container talk to your machine's Docker engine, so it can launch sibling containers for transcriptomics, MOFA, etc. |
| `-v "<host-folder>:/shared"` | Your input files, the run configuration (`COMBINED_COMMANDS.json`), and all results live here. Put your metadata and data files here before starting an analysis. |

Two more variables are already baked into the image with sensible defaults and normally don't need to be set manually: `BIOMIX_RUNNING_IN_DOCKER=true` and `BIOMIX_DATA_DIR=/shared`.

### Optional: NCBI API key

The PubMed literature-mining step works without one, but is rate-limited (3 requests/second). Add `-e NCBI_API_KEY=<your-key>` to raise that limit — get a free key at [ncbi.nlm.nih.gov/account/settings](https://www.ncbi.nlm.nih.gov/account/settings).

### Using a different local port

```bash
docker run -p 8080:3838 --rm -it \
  -e BIOMIX_HOST_SHARED_PATH="/path/to/your/shared/folder" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "/path/to/your/shared/folder:/shared" \
  ghcr.io/biomix-consortium/biomix-gui:V2
```

Then open `http://localhost:8080`.

---

## Running a script inside an analysis image (advanced / debugging)

This is normally handled automatically by `BiomiX_BETA.r` running inside `biomix-gui` — you shouldn't need to do this by hand in regular use. It's documented here for debugging a specific analysis image in isolation.

The general pattern:

```
docker run --rm \
  -v <host-shared-dir>:/shared \
  <image> \
  Rscript <path-to-script> <DIRECTORY> <CELL_TYPE_LABEL> <GROUP_1> <GROUP_2> <SHARED_DIR> <ITERATIONS>
```

> **What does this mean?**
> - `--rm` — remove the container automatically when it exits.
> - `-v <host-shared-dir>:/shared` — mounts your shared data folder (the one containing `COMBINED_COMMANDS.json` and your input files) so the script can read inputs and write results back to disk.
> - The trailing arguments after the script path are positional: the BiomiX install directory inside the image (normally `/opt/biomix/BiomiX2.5`), the dataset label to process, the two comparison groups, the shared data directory (normally `/shared`), and the iteration counter.

**Example — run `Biomix_DGE_GENES_LIMMA.r` against a local workspace:**

```bash
docker run --rm \
  -v /path/to/my/biomix_workspace:/shared \
  ghcr.io/biomix-consortium/biomix-transcriptomics:V2 \
  Rscript /opt/biomix/BiomiX2.5/Transcriptomics/Biomix_DGE_GENES_LIMMA.r \
  /opt/biomix/BiomiX2.5 MyCellType GroupA GroupB /shared 1
```

`/path/to/my/biomix_workspace` should follow the BiomiX2.5 shared-folder structure (containing `COMBINED_COMMANDS.json`, and the relevant `INPUT`/`OUTPUT` subfolders). Installation files, reference databases, and R packages come from the image itself; only data and results are read from/written to the mounted folder.

---

## Troubleshooting

- **"port is already allocated" when starting the GUI**: another BiomiX container is likely still running from a previous session. Run `docker ps`, find it, and `docker stop <container-id>`.
- **A sibling image "not found" when BiomiX tries to launch an analysis**: that component hasn't been pulled yet. Pull it manually (see [Pulling images](#pulling-images)) or use the launcher's component checklist.
- **Docker build fails under `arm64` with compiler or "Exec format error" issues**: this is a known QEMU emulation limitation for R/Bioconductor packages — see the note under [Building images locally](#building-images-locally).
