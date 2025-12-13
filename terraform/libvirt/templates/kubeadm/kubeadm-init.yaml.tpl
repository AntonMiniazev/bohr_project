
#kubeadmin-config
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${control_plane_ip}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ampere-main
kubernetesVersion: ${k8s_version}
controlPlaneEndpoint: "${control_plane_ip}:6443"
networking:
  podSubnet: ${pod_network_cidr}
  serviceSubnet: ${service_subnet}
controllerManager:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"
scheduler:
  extraArgs:
    - name: "bind-address"
      value: "0.0.0.0"