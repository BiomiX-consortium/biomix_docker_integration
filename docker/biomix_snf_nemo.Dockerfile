FROM ghcr.io/biomix-consortium/biomix-base:V2

LABEL org.opencontainers.image.description="BiomiX SNF/NEMO image — similarity network fusion clustering"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to SNF/NEMO.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    install.packages(c('visNetwork', 'fpc', 'aricode', 'ggalluvial', 'survival', 'survminer', 'SNFtool', 'pheatmap', 'rlist'))"

# NEMO — only available on GitHub, not CRAN.
RUN Rscript -e " \
    devtools::install_github('Shamir-Lab/NEMO/NEMO')"