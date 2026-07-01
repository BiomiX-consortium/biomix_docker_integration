FROM ghcr.io/biomix-consortium/biomix-base:latest

LABEL org.opencontainers.image.description="BiomiX GUI — Shiny frontend"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

WORKDIR /opt/biomix/BiomiX2.5

# Keep site-library (.Library.site) on .libPaths() after renv::load() so base-image
# packages (tidyverse, vroom, etc.) remain accessible at runtime.
ENV RENV_CONFIG_SANDBOX_ENABLED=FALSE

RUN Rscript -e "install.packages('renv', repos = 'https://cloud.r-project.org')"

# Init the renv project, then install packages through renv so they land in the
# project library — the first path renv::load() will search at runtime.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    renv::init(project = '_INSTALL', bare = TRUE); \
    renv::install('shiny@1.9.1'); \
    renv::install('shinythemes'); \
    renv::install('shinyjs'); \
    renv::install('shinyFiles'); \
    renv::install('readxl'); \
    renv::install('mice'); \
    renv::install('data.table'); \
    renv::install('DT'); \
    renv::install('bioc::mixOmics')"

EXPOSE 3838

ENTRYPOINT ["Rscript", "-e", "shiny::runApp('.', host='0.0.0.0', port=3838, launch.browser=FALSE)"]
