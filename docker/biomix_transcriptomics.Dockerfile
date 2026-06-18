FROM ghcr.io/biomix-consortium/biomix-base:latest

LABEL org.opencontainers.image.description="BiomiX transcriptomics image — DESeq2, edgeR, limma"

# CRAN packages specific to transcriptomics.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    remotes::install_version('enrichR', version = '3.2', upgrade = 'never')"

# Bioconductor packages specific to transcriptomics.
RUN Rscript -e " \
    BiocManager::install(c('DESeq2', 'edgeR', 'limma'), ask = FALSE, update = FALSE)"
