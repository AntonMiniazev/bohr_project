# Custom Images

This folder contains Dockerfiles and build context for custom images used by the platform (for example Airflow-related images used by Helmfile releases).

Typical workflow:
1) Edit the Dockerfile under the relevant subfolder.
2) Build and push the image to the registry used by Helmfile.
3) Update the Helmfile values to point to the new image tag.
