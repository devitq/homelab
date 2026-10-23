helm repo add coredns https://coredns.github.io/helm
helm upgrade --install coredns coredns/coredns --namespace kube-system
