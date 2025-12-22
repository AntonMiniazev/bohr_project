apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "${bootstrap_token}"
    apiServerEndpoint: ${control_plane.ip}:6443
    caCertHashes:
      - "${ca_cert_hash}"
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cloud-provider: "none"
    node-ip: ${node_ip}
