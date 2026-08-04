FROM ghcr.io/biomix-consortium/biomix-base:V2

LABEL org.opencontainers.image.description="BiomiX metabolomics image — MSnbase, QFeatures, Spectra"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# NOTE: the conda environment targets Bioconductor 3.22, whereas the base image
# uses Bioconductor 3.21. Verify package compatibility before running gold tests.

# System library required by some metabolomics R packages.
RUN apt-get update \
    && apt-get install -y --no-install-recommends zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# CRAN packages specific to metabolomics — versioned.
RUN Rscript -e " \
    options(repos = c(CRAN = 'https://cloud.r-project.org')); \
    remotes::install_version('rlist', version = '0.4.6.2', upgrade = 'never')"

# CRAN packages specific to metabolomics — unversioned.
RUN Rscript -e " \
    install.packages(c( \
        'httr', 'progress', 'RJSONIO', 'cli', 'png', \
        'openxlsx', 'igraph', 'plotly', 'reshape2', \
        'ggforce', 'graphlayouts', 'tidygraph', 'viridis', 'ggraph', \
        'future', 'furrr', 'ComplexUpset', 'bookdown', \
        'MALDIquant', 'RUnit', 'ncdf4', 'patchwork' \
    ), repos = 'https://cloud.r-project.org')"

# GitHub packages specific to metabolomics.
RUN Rscript -e " \
    remotes::install_github('lzyacht/cmmr', upgrade = 'never'); \
    remotes::install_github('tidymass/metpath', upgrade = 'never')"

# Bioconductor packages specific to metabolomics.
RUN Rscript -e " \
    BiocManager::install(c( \
        'S4Vectors', 'IRanges', 'XVector', 'Biobase', \
        'GenomicRanges', 'S4Arrays', 'SparseArray', 'DelayedArray', \
        'SummarizedExperiment', 'MultiAssayExperiment', 'QFeatures', \
        'BiocParallel', 'Spectra', 'Rhdf5lib', 'MetaboCoreUtils', \
        'AnnotationFilter', 'affy', 'preprocessCore', \
        'mzID', 'mzR', 'pcaMethods', 'impute', 'vsn', \
        'PSMatch', 'MSnbase', 'BiocStyle' \
    ), ask = FALSE, update = FALSE)"