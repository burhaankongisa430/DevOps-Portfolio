package main

# Resources that carry pod specs
_pod_containers[container] {
  input.kind == "Rollout"
  container := input.spec.template.spec.containers[_]
}

_pod_containers[container] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
}

# Using :latest is non-deterministic — two deploys of the same manifest can
# run different code. Every image in the pipeline is tagged sha-<git-sha> so
# every deploy is traceable to a specific commit.
deny[msg] {
  container := _pod_containers[_]
  endswith(container.image, ":latest")
  msg := sprintf(
    "container '%s' uses ':latest' tag — pin to a specific sha-<git-sha> tag",
    [container.name],
  )
}
