# New Service Template

The `portfolio new <name>` command generates a new service from the golden path.
Templates are embedded directly in `cli/portfolio/commands/new_service.py` and rendered
at runtime — no external template engine required.

Generated service structure:
```
<service-name>/
├── app/
│   ├── main.go        Go HTTP service with /health, /, /metrics
│   ├── go.mod
│   └── Dockerfile     Multi-stage distroless build
├── helm/<service-name>/
│   ├── Chart.yaml
│   └── values.yaml    Argo Rollout with canary strategy
├── argocd/
│   └── <service-name>.yaml  ArgoCD Application (add to project-3-gitops/argocd/apps/)
└── catalog-info.yaml  Backstage Component entry
```

To generate:
```bash
portfolio new payment-service
```
