MANIFEST_DIR := env_var_or_default("MANIFEST_DIR", "proxmox/manifests")
K8S_VERSION := env_var_or_default("K8S_VERSION", "1.36.1")

fmt:
    yamlfmt .

fmt-check:
    yamlfmt -lint .

lint-yaml:
    yamllint .

lint-k8s:
    kube-linter lint --config .kube-linter.yaml {{MANIFEST_DIR}}

validate:
    kubeconform -strict -summary -ignore-missing-schemas \
        -kubernetes-version {{K8S_VERSION}} {{MANIFEST_DIR}}

lint: lint-yaml lint-k8s validate

lint-all: fmt-check lint

install-hooks:
    pre-commit install
