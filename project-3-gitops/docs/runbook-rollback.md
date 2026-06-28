# Runbook: Rollback a Canary Deployment

**When to use this:** A canary is in progress and you need to stop it — either because the automated analysis failed and you want to confirm the abort, or because you observed a problem that the analysis didn't catch (user reports, external monitoring, gut instinct).

---

## How Automatic Rollback Works

When an AnalysisRun fails (the `/health` endpoint returns non-`"ok"` for more than `failureLimit` consecutive checks), Argo Rollouts:

1. Sets the Rollout phase to `Degraded`
2. Sets canary traffic weight back to **0%** — all traffic returns to the stable service instantly
3. Scales the canary ReplicaSet down to 0 pods
4. Leaves the stable ReplicaSet unchanged

The rollback is **instantaneous at the traffic layer** (ALB annotation is updated) and then completes at the pod layer over the next termination grace period (30 seconds by default).

---

## Manual Abort (in-flight rollout)

If you see a problem during a canary and don't want to wait for the analysis to detect it:

```bash
# Immediately abort: traffic returns 100% to stable
kubectl argo rollouts abort app -n default

# Watch the abort complete
kubectl argo rollouts get rollout app -n default --watch
```

Expected output after abort:
```
Name:            app
Namespace:       default
Status:          ✖ Aborted
Strategy:        Canary
  Step:          0/6
  SetWeight:     0
  ActualWeight:  0
```

---

## Retry After an Abort

An aborted rollout stays in `Aborted` state. To retry the same image tag:

```bash
kubectl argo rollouts retry rollout app -n default
```

To deploy a different (fixed) image tag instead, update `image.tag` in `argocd/apps/portfolio-app.yaml` and push — ArgoCD will sync and trigger a fresh rollout.

---

## Manual Promotion (bypass pauses)

During a `pause` step, if you're confident the canary is healthy and want to skip the wait:

```bash
# Promote past the current pause to the next step
kubectl argo rollouts promote app -n default

# Promote ALL remaining steps at once (skip remaining pauses and analysis)
kubectl argo rollouts promote app -n default --full
```

Use `--full` only when you are certain the release is safe — it skips all remaining analysis gates.

---

## Check Rollout Status

```bash
# Summary view
kubectl argo rollouts get rollout app -n default

# Live watch (updates every 1s)
kubectl argo rollouts get rollout app -n default --watch

# View AnalysisRun results
kubectl get analysisrun -n default
kubectl describe analysisrun <run-name> -n default
```

---

## Check Traffic Split (ALB)

```bash
# View the annotation Argo Rollouts has injected on the Ingress
kubectl get ingress app -n default -o jsonpath='{.metadata.annotations}' | python3 -m json.tool
```

During a 20% canary you will see something like:
```json
{
  "alb.ingress.kubernetes.io/actions.app-stable": "{\"type\":\"forward\",\"forwardConfig\":{\"targetGroups\":[{\"serviceName\":\"app-stable\",\"servicePort\":\"80\",\"weight\":80},{\"serviceName\":\"app-canary\",\"servicePort\":\"80\",\"weight\":20}]}}"
}
```

---

## Emergency: Full Rollback via Git

If the Argo Rollouts controller itself is unavailable, revert the image tag in `argocd/apps/portfolio-app.yaml` to the last-known-good value and push. ArgoCD will sync a standard Helm upgrade that replaces all pods with the old image.

```bash
# Find the last good image tag in git history
git log --oneline argocd/apps/portfolio-app.yaml

# Revert the file to a specific commit
git checkout <commit-hash> -- argocd/apps/portfolio-app.yaml
git commit -m "revert: emergency rollback to <commit-hash>"
git push
```

ArgoCD detects the push within `timeout.reconciliation` (30 seconds by default) and applies the revert.

---

## Incident Post-Mortem Template

After any unplanned rollback, document the incident with these headings:

1. **Timeline** — when the deploy started, when the issue was detected, when traffic was restored
2. **Impact** — which users were affected, for how long, and what they experienced
3. **Root cause** — what changed and why it caused the failure
4. **Detection** — did the automated analysis catch it? If not, what missed it?
5. **Remediation** — what fixed it in the short term
6. **Prevention** — what would stop this from happening again (better analysis, a new test, etc.)

Publish the post-mortem as `docs/postmortem-YYYY-MM-DD.md` in this repo. Treat it as a high-signal portfolio artefact — it demonstrates you operate like a senior engineer, not just someone who deploys and moves on.
