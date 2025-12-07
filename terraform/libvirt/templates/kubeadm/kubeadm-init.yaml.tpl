
#kubeadmin-config
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
skipPhases:
  - addon/kube-proxy
localAPIEndpoint:
  advertiseAddress: ${control_plane.ip}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: ${control_plane.ip}
    - name: cgroup-driver
      value: systemd  
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ${packages.kubernetes.cluster_name}
kubernetesVersion: ${packages.kubernetes.k8s_version}
controlPlaneEndpoint: "${control_plane.ip}:6443"
networking:
  podSubnet: ${packages.cilium.pod_network_cidr}
  serviceSubnet: ${packages.kubernetes.service_subnet}
controllerManager:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"
    - name: "allocate-node-cidrs"
      value: "true"
    - name: "node-cidr-mask-size-ipv4"
      value: "24"
scheduler:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"
