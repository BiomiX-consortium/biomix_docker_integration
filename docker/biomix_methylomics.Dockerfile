FROM ghcr.io/biomix-consortium/biomix-base:latest

LABEL org.opencontainers.image.description="BiomiX methylomics image — ChAMP"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to methylomics.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    remotes::install_version('rjson',       version = '0.2.21', upgrade = 'never'); \
    remotes::install_version('data.table',  version = '1.15.4', upgrade = 'never'); \
    remotes::install_version('matrixStats', version = '1.3.0',  upgrade = 'never'); \
    remotes::install_version('enrichR',     version = '3.2',    upgrade = 'never')"

# Bioconductor packages specific to methylomics.
RUN Rscript -e " \
    BiocManager::install('ChAMP', ask = FALSE, update = FALSE)"
