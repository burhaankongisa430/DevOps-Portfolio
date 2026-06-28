package main

_pod_containers[container] {
  input.kind == "Rollout"
  container := input.spec.template.spec.containers[_]
}

_pod_containers[container] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
}

# A privileged container has nearly the same access to the host as a process
# running directly on the node — it can mount host filesystems, load kernel
# modules, and escape container isolation entirely.
deny[msg] {
  container := _pod_containers[_]
  container.securityContext.privileged == true
  msg := sprintf(
    "container '%s' runs as privileged — this grants host-level access and is never acceptable",
    [container.name],
  )
}

# hostPID lets the container see all processes on the host — a common
# privilege-escalation path when combined with /proc access.
deny[msg] {
  input.kind == "Rollout"
  input.spec.template.spec.hostPID == true
  msg := "hostPID: true exposes host process table — denied"
}

deny[msg] {
  input.kind == "Rollout"
  input.spec.template.spec.hostNetwork == true
  msg := "hostNetwork: true bypasses network policy — denied"
}
