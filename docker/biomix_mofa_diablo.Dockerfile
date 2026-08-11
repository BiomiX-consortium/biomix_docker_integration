ARG BASE_TAG=latest
FROM ghcr.io/biomix-consortium/biomix-base:${BASE_TAG}

LABEL org.opencontainers.image.description "BiomiX MOFA/DIABLO image — MOFA2, DESeq2, mixOmics"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to MOFA/DIABLO.
RUN Rscript -e " \
    install.packages( \
        c('data.table', 'caret', 'rlist', 'reticulate', 'GGally', 'ggpubr'), \
        repos = 'https://cloud.r-project.org')"

# Bioconductor packages specific to MOFA/DIABLO.
RUN Rscript -e " \
    BiocManager::install(c('DESeq2', 'MOFA2', 'mixOmics'), ask = FALSE, update = FALSE)"

# Install mofapy2 into the base image's existing Python venv, and pin
# RETICULATE_PYTHON so reticulate never tries to auto-provision an
# environment at runtime (see the basilisk/uv issue encountered earlier).
RUN /opt/py-env/bin/pip install --no-cache-dir mofapy2

ENV RETICULATE_PYTHON=/opt/py-env/bin/python3