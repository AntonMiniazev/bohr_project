# Archived Unity Catalog deployment

This chart and its SOPS-encrypted credential manifest are retained for deployment history. The active Helmfile no longer references this directory. The last active release definition and environment values are available in Git history at commit `867971c` (`helmfile/helmfile.yaml` and `helmfile/env.yaml`).

The live release, namespace, and dedicated PostgreSQL database and role were removed after the Iceberg/Lakekeeper cutover. Do not apply this chart to the current cluster.
