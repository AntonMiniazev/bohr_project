# syntax=docker/dockerfile:1.7

############################
# Stage: dev (VS Code devcontainer)
############################
FROM mcr.microsoft.com/devcontainers/python:3.11 AS dev

# Helm
ARG HELM_VERSION=v4.0.0
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
ARG KUBECTL_VERSION=v1.31.2
RUN curl -fsSL https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl

# Helmfile
ARG HELMFILE_VERSION=v1.2.2
RUN curl -fsSL https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_amd64.tar.gz \
    | tar -xz \
 && mv helmfile /usr/local/bin/helmfile \
 && chmod +x /usr/local/bin/helmfile

# helm-secrets and diff plugins
RUN helm plugin install https://github.com/jkroepke/helm-secrets --version v4.7.4 
RUN helm plugin install https://github.com/databus23/helm-diff

# Base system tools for infra / terraform
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    git \
    gnupg \
    openssh-client \
    jq \
    make \
 && rm -rf /var/lib/apt/lists/*

# Install Terraform (official HashiCorp repo)
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com jammy main" \
    > /etc/apt/sources.list.d/hashicorp.list \
 && apt-get update \
 && apt-get install -y terraform \
 && rm -rf /var/lib/apt/lists/* \
 && curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

RUN curl -sSL https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64 \
     -o /usr/local/bin/sops && chmod +x /usr/local/bin/sops

# Initialize Microsoft ODBC 18
#RUN curl -sSL -O https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb && \
#    dpkg -i packages-microsoft-prod.deb || true && \
#    apt-get update && \
#    apt-get install -y --fix-broken && \
#    ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev && \
#    rm -f packages-microsoft-prod.deb && \
#    rm -rf /var/lib/apt/lists/* && \
#    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# UV
WORKDIR /workspace
COPY pyproject.toml uv.lock ./
RUN pipx install uv && uv sync

############################
# Stage: dbt-runner
############################
FROM python:3.11-slim AS dbt-runner
ENV PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl tini \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir uv

# Initialize Microsoft ODBC 18
#RUN curl -sSL -O https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb && \
#    dpkg -i packages-microsoft-prod.deb || true && \
#    apt-get update && \
#    apt-get install -y --fix-broken && \
#    ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev && \
#    rm -f packages-microsoft-prod.deb && \
#    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install runtime deps
COPY pyproject.toml uv.lock /app/
RUN uv sync --no-dev  # creates /app/.venv

# Copy full dbt project (dbt_project.yml, models, selectors.yml, etc.)
COPY dbt/ /app/project/

# Resolve dbt packages at build time
RUN . /app/.venv/bin/activate && dbt --version && dbt deps --project-dir /app/project

# Entrypoints
ENV PATH="/app/.venv/bin:${PATH}" DBT_PROFILES_DIR="/app/profiles"
COPY docker/entrypoints/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/run_dbt.sh"]
