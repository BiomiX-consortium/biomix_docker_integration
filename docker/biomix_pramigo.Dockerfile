ARG BASE_TAG=latest
FROM ghcr.io/biomix-consortium/biomix-base:${BASE_TAG}

LABEL org.opencontainers.image.description="BiomiX PRAMIGO image — Python/PyTorch graph analysis tool"
LABEL org.opencontainers.image.source https://github.com/BiomiX-consortium/biomix_docker_integration

# Install uv — lets us pin an exact Python version (3.8) independently of
# whatever Ubuntu ships by default, without adding third-party apt repos.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# PRAMIGO needs its own Python 3.8 environment (torch 1.13.1 requires an
# older Python than other tools in this project), kept in its own venv so
# it never conflicts with any other Python environment in the image.
#
# Requirements are written directly here (instead of a separate
# requirements-pramigo.txt file) to keep everything in one place.
RUN cat <<'EOF' > /tmp/requirements-pramigo.txt
torch==1.13.1
torch-geometric==2.5.3
numpy==1.23.1
pandas==2.0.3
scipy==1.10.1
scikit-learn==1.3.2
networkx==2.5
matplotlib==3.7.5
seaborn==0.13.2
umap-learn==0.5.6
plotly
dill
tqdm==4.66.2
python-igraph
leidenalg
EOF

RUN uv venv --python 3.8 /opt/pramigo-env && \
    uv pip install --python /opt/pramigo-env/bin/python -r /tmp/requirements-pramigo.txt