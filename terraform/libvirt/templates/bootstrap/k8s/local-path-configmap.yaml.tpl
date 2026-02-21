
#local-path-configmap
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |
    {
      "storageClassConfigs": {
        "local-path": {
          "nodePathMap": [
            {
              "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
              "paths": ["/opt/local-path-provisioner"]
            }
          ]
        },
        "local-path-shared": {
          "sharedFileSystemPath": "/opt/local-path-provisioner/shared"
        }
      }
    }
  setup: |-
    #!/bin/sh
    set -eu
    mkdir -m 0777 -p "$VOL_DIR"
  teardown: |-
    #!/bin/sh
    set -eu
    rm -rf "$VOL_DIR"
  helperPod.yaml: |-
      apiVersion: v1
      kind: Pod
      metadata:
        name: helper-pod
      spec:
        priorityClassName: system-node-critical
        tolerations:
          - key: node.kubernetes.io/disk-pressure
            operator: Exists
            effect: NoSchedule
        containers:
        - name: helper-pod
          image: busybox
          imagePullPolicy: IfNotPresent
