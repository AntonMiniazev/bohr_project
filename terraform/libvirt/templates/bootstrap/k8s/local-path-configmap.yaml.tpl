
#local-path-configmap
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |
    {
      "sharedFileSystemPath": "/opt/local-path-provisioner/shared"
    }
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