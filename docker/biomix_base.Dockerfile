FROM bioconductor/bioconductor_docker:RELEASE_3_21-R-4.5.2

LABEL org.opencontainers.image.description="BiomiX base image — R 4.5.2, Bioconductor 3.21, Python venv"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

WORKDIR /opt/biomix

COPY docker/requirements.txt .

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        python3 \
        python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/py-env \
    && /opt/py-env/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/py-env/bin/pip install --no-cache-dir -r requirements.txt

# We currently get the HEAD of the main branch.
RUN git clone --depth 1 https://github.com/BiomiX-consortium/BiomiX2.5.git

ENV PATH="/opt/py-env/bin:$PATH"

# Install remotes first — needed for install_version() below.
RUN Rscript -e "install.packages('remotes', repos='https://cloud.r-project.org')"

RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    remotes::install_version('vroom',     version = '1.6.5',  upgrade = 'never'); \
    remotes::install_version('readxl',    version = '1.4.3',  upgrade = 'never'); \
    remotes::install_version('jsonlite',  version = '1.8.8',  upgrade = 'never'); \
    remotes::install_version('tidyverse', version = '2.0.0',  upgrade = 'never'); \
    remotes::install_version('ggrepel',   version = '0.9.5',  upgrade = 'never'); \
    remotes::install_version('circlize',  version = '0.4.16', upgrade = 'never')"

RUN Rscript -e "BiocManager::install('ComplexHeatmap', ask = FALSE, update = FALSE)"
RUN Rscript -e "BiocManager::install('mixOmics', ask = FALSE, update = FALSE)"
