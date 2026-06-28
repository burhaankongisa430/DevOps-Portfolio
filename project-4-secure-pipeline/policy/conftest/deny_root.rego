package main

_pod_containers[container] {
  input.kind == "Rollout"
  container := input.spec.template.spec.containers[_]
}

_pod_containers[container] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
}

# Running as root inside a container is unnecessary and dangerous: if the
# container escapes, the attacker has root on the host. The distroless image
# runs as uid 65532 (nonroot) by default; this policy enforces it at the
# manifest layer so a misconfigured values.yaml is caught before deploy.

deny[msg] {
  container := _pod_containers[_]
  container.securityContext.runAsUser == 0
  msg := sprintf(
    "container '%s' sets runAsUser: 0 (root) — use a non-zero uid",
    [container.name],
  )
}

deny[msg] {
  input.kind == "Rollout"
  input.spec.template.spec.securityContext.runAsNonRoot != true
  msg := "pod securityContext must set runAsNonRoot: true"
}

# Capability drops reduce the blast radius of a container compromise.
# NET_RAW alone allows ARP spoofing and network sniffing — it must be dropped.
warn[msg] {
  container := _pod_containers[_]
  caps := container.securityContext.capabilities
  not caps.drop
  msg := sprintf(
    "container '%s' does not drop any Linux capabilities — consider dropping ALL",
    [container.name],
  )
}
