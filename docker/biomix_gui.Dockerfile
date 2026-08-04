FROM ghcr.io/biomix-consortium/biomix-base:V2

LABEL org.opencontainers.image.description="BiomiX GUI — Shiny frontend"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

WORKDIR /opt/biomix/BiomiX2.5

ENV BIOMIX_RUNNING_IN_DOCKER=true
ENV BIOMIX_DATA_DIR=/shared

# Keep site-library (.Library.site) on .libPaths() after renv::load() so base-image
# packages (tidyverse, vroom, etc.) remain accessible at runtime.
ENV RENV_CONFIG_SANDBOX_ENABLED=FALSE

# Docker CLI — needed so this container can launch sibling containers
# (transcriptomics, metabolomics, etc.) via the mounted host socket.
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

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
    renv::install('tidyverse'); \
    renv::install('rlist'); \
    renv::install('openxlsx'); \
    renv::install('bioc::mixOmics')"

EXPOSE 3838

ENTRYPOINT ["Rscript", "-e", "shiny::runApp('.', host='0.0.0.0', port=3838, launch.browser=FALSE)"]