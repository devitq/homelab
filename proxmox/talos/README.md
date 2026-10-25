# Taloslinux Configurations

## Image configuration

```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/amd-ucode
            - siderolabs/amdgpu
            - siderolabs/ctr
            - siderolabs/nonfree-kmod-nvidia-production
            - siderolabs/qemu-guest-agent
```

## Cheatsheet

```bash
talosctl gen secrets -o secrets.yaml --talos-version v1.12.0 --force

talosctl gen config cluster https://10.13.45.1:6443 \
	-o talosconfig --output-types talosconfig \
	--talos-version v1.12.0 \
	--with-secrets secrets.yaml --force

talosctl gen config cluster https://10.13.45.1:6443 \
	--kubernetes-version 1.36.2 --talos-version 1.13 \
	-o rendered/cp-01.yaml --output-types controlplane \
	--additional-sans k8s.lan,k8s.itqdev.xyz --with-cluster-discovery --with-docs --with-examples \
	--with-secrets secrets.dec.yaml \
	--config-patch @patches/allow-controlplane-workloads.yaml \
	--config-patch @patches/disable-cni-and-kubeproxy.yaml \
	--config-patch @patches/enable-user-namespaces.yaml \
	--config-patch @patches/custom-image.yaml \
	--config-patch @patches/namespaces.yaml \
	--config-patch @patches/pod-security.yaml \
	--config-patch @patches/kubeapi-optimization.yaml \
	--config-patch @patches/services-bind-fix.yaml \
	--config-patch @patches/control-plane-limits.yaml \
	--config-patch @patches/k8s-talos-api-access.yaml \
	--config-patch @patches/disable-auditd.yaml \
	--config-patch @patches/subnets.yaml \
	--config-patch @patches/registry-mirrors.yaml \
	--config-patch @patches/sysctls.yaml \
	--config-patch @nodes/cp-01.yaml \
	--force

talosctl apply-config -n 10.13.10.164 -f rendered/cp-01.yaml --insecure -m auto
```

## Troubleshooting

```bash
talosctl processes
talosctl cgroups
```
