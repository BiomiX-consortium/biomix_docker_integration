FROM ghcr.io/biomix-consortium/biomix-base:latest

LABEL org.opencontainers.image.description="BiomiX MOFA image — MOFA2, DESeq2"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to MOFA.
# No versions are pinned in the conda environment, so latest compatible is used.
RUN Rscript -e " \
    install.packages( \
        c('data.table', 'caret', 'rlist', 'reticulate'), \
        repos = 'https://cloud.r-project.org')"

# Bioconductor packages specific to MOFA.
RUN Rscript -e " \
    BiocManager::install(c('DESeq2', 'MOFA2'), ask = FALSE, update = FALSE)"
