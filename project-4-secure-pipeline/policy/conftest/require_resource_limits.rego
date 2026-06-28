package main

_pod_containers[container] {
  input.kind == "Rollout"
  container := input.spec.template.spec.containers[_]
}

_pod_containers[container] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
}

# Without memory limits a single pod can exhaust node memory and cause OOM kills
# on neighbouring pods. Without CPU limits the scheduler cannot guarantee fair
# sharing. Both are required for production workloads.

deny[msg] {
  container := _pod_containers[_]
  not container.resources.limits.memory
  msg := sprintf(
    "container '%s' has no memory limit — required for cluster stability",
    [container.name],
  )
}

deny[msg] {
  container := _pod_containers[_]
  not container.resources.limits.cpu
  msg := sprintf(
    "container '%s' has no CPU limit — required for fair scheduling",
    [container.name],
  )
}

deny[msg] {
  container := _pod_containers[_]
  not container.resources.requests.memory
  msg := sprintf(
    "container '%s' has no memory request — the scheduler cannot place pods correctly without it",
    [container.name],
  )
}
