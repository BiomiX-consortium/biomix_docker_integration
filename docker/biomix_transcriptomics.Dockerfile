ARG BASE_TAG=latest
FROM ghcr.io/biomix-consortium/biomix-base:${BASE_TAG}

LABEL org.opencontainers.image.description "BiomiX transcriptomics image — DESeq2, edgeR, limma"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to transcriptomics.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    remotes::install_version('enrichR', version = '3.2', upgrade = 'never')"

# Bioconductor packages specific to transcriptomics.
RUN Rscript -e " \
    BiocManager::install(c('DESeq2', 'edgeR', 'limma'), ask = FALSE, update = FALSE)"