FROM ghcr.io/biomix-consortium/biomix-base:V2

LABEL org.opencontainers.image.description="BiomiX interpretation image — pathway/enrichment/literature interpretation"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# CRAN packages specific to interpretation.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    install.packages(c('enrichR', 'vroom', 'tidyverse', 'dplyr', 'XML', 'xml2', 'stringr', 'rentrez', 'readxl'))"

# GitHub packages specific to interpretation.
RUN Rscript -e " \
    remotes::install_github('tidymass/metpath', upgrade = 'never'); \
    remotes::install_github('elizagrames/litsearchr', ref = 'main', upgrade = 'never')"