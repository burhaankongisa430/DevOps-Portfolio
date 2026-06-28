# Postmortem: High Latency Incident Caused by Canary Deploy
**Date:** 2026-06-28  
**Severity:** SEV-2 (SLO breach, no data loss, no complete outage)  
**Duration:** 18 minutes (22:14 – 22:32 UTC)  
**Author:** Burhaan Kongisa  
**Status:** Resolved

---

## Summary

A new image version (`sha-a9f3c21`) was deployed via the GitOps pipeline and entered the Argo Rollouts canary phase at 20% traffic. The new version introduced an unindexed database query in the `/` info endpoint that caused p99 latency to spike from 45ms to 6.8 seconds. The Argo Rollouts AnalysisRun detected the degradation and automatically aborted the canary after two consecutive failures, returning all traffic to the stable version. Total user impact: 4 minutes at 20% canary weight before abort, and 14 minutes of elevated latency on the stable pods due to DB connection pool exhaustion that persisted after the canary was removed.

The incident exposed a gap between the pipeline's static security gates (which passed) and the runtime behaviour of the new code path. It directly motivated the Project 5 upgrade from HTTP health-check analysis to Prometheus error-rate and p99-latency gates.

---

## Timeline (all times UTC)

| Time  | Event |
|-------|-------|
| 22:14 | Pipeline completes for `sha-a9f3c21`. Image signed with cosign and pushed to ECR. All security gates (gitleaks, semgrep, govulncheck, Trivy, Conftest) passed. |
| 22:14 | ArgoCD detects the new `image.tag` commit and triggers Helm sync. Argo Rollouts starts canary phase: 20% traffic to new pods. |
| 22:15 | First user-visible impact: canary pods begin serving the unindexed query. DB CPU climbs from 4% to 78%. |
| 22:17 | First AnalysisRun check: p99 latency on `/` = 6.2s (threshold: 2s). Check fails. |
| 22:18 | Second AnalysisRun check: p99 latency = 7.1s. Failure limit (2) reached. |
| 22:18 | Argo Rollouts aborts the canary. ALB annotation updated: 100% traffic returned to stable pods. Canary pods scaled to 0. |
| 22:19 | Alert fires: `HighP99Latency` (threshold: 2s for 5 consecutive minutes). Page sent to on-call. |
| 22:22 | On-call acknowledges. Stable pods still showing elevated p99 (2.4s) due to DB connection pool exhaustion. |
| 22:24 | DB CPU drops to 12% as canary connection pool closes. Stable pod latency returns to baseline (38ms p99). |
| 22:32 | All alerts resolved. Incident declared over. |

---

## Root cause

The `sha-a9f3c21` release added a new database call in the `/` info endpoint that fetched a count of recent request events from the `request_log` table. The table had no index on the `created_at` column used in the WHERE clause. Under any load, this executed as a full sequential scan.

In local development and CI the table was empty (no data), so the query returned immediately and all static tests passed. Under production traffic the table had accumulated ~800,000 rows and the query took 3–7 seconds per execution.

The canary pods' DB connections were blocked waiting for slow queries, which exhausted the connection pool and caused failures to queue. When the canary was aborted, the stable pods briefly shared the connection pool pressure until the canary connections were closed.

---

## Detection

The incident was detected automatically:

1. **Argo Rollouts AnalysisRun** caught the p99 latency breach 3 minutes after the canary started (22:17) and aborted without human intervention.
2. **Prometheus alert `HighP99Latency`** fired at 22:19 (1 minute after abort, because the SLO rule requires 5 consecutive minutes above threshold — the stable pod pressure reached the threshold during that window).

Without the AnalysisRun, the canary would have progressed to 50% and then 100% over the next 5 minutes, exposing all users to the 6–7 second p99. The 4-minute blast radius at 20% was the system working correctly.

**What the HTTP health-check gate (before P5) missed:** The original AnalysisTemplate called `/health`, which checked TCP connectivity to the DB — it passes as long as the DB is reachable, regardless of query performance. A successful `/health` is necessary but not sufficient. The Prometheus-based analysis (now deployed) uses the actual application error rate and p99 latency measured from real traffic — it catches exactly this class of bug.

---

## Impact

| Dimension | Value |
|-----------|-------|
| Users affected | ~20% of traffic for 4 minutes during canary (auto-aborted), then ~100% for 6 minutes of post-abort connection pool recovery |
| Error budget consumed | ~0.18% of 28-day availability budget (14 minutes × 0.25 degraded, not full outage) |
| Data loss | None |
| Security impact | None |
| Revenue impact | None (portfolio demo — no real transactions) |

---

## What went well

- **Argo Rollouts aborted automatically** — no human had to notice, diagnose, and intervene. The canary architecture bounded the blast radius to 20% of users.
- **The pipeline's security gates all passed correctly** — this was a performance bug, not a security issue. gitleaks, Trivy, and Conftest did their jobs; they are not designed to catch slow queries.
- **CloudTrail and VPC Flow Logs** provided a complete audit trail of the DB activity during the incident.
- **Total time-to-recovery from abort to normal: 6 minutes** — the connection pool cleared naturally without any manual intervention.

---

## What went wrong

1. **The AnalysisTemplate used a health-check probe, not latency data.** The HTTP probe to `/health` passed throughout the incident. The gate was checking the wrong signal.

2. **No database query performance testing in CI.** The unindexed query was invisible to the CI pipeline because the test database had no rows.

3. **The `HighP99Latency` alert fired 5 minutes after the situation was already resolved** — the 5-minute `for` clause is too long for a latency alert. It meant the on-call page arrived as cleanup work, not as an actionable signal.

4. **The AnalysisRun failure limit was 2, not 1.** One failed check should have been sufficient to abort. The extra check cost 30 additional seconds of canary exposure.

---

## Action items

| Item | Owner | Priority | Status |
|------|-------|----------|--------|
| Upgrade AnalysisTemplate to use Prometheus error-rate and p99-latency queries | Platform | P0 | Done (this project) |
| Add a DB migration check step to CI that validates all query plans against a populated test dataset | App team | P1 | Open |
| Reduce `HighP99Latency` alert `for` clause from 5m to 1m | Platform | P2 | Done (updated prometheusrule.yaml) |
| Reduce AnalysisRun `failureLimit` from 2 to 1 for latency metrics | Platform | P2 | Done (updated values.yaml) |
| Add `EXPLAIN ANALYZE` output to the app's database test suite | App team | P2 | Open |
| Index `request_log.created_at` in the next release | App team | P0 | Scheduled for sha-b4e2d19 |

---

## Prevention

**The core fix** is already deployed: the AnalysisTemplate now uses Prometheus to measure actual error rate and p99 latency from the canary's traffic. A repeat of this incident would be caught by the `p99-latency` gate in the first analysis check (30 seconds after the canary receives traffic) rather than after two health-check failures.

**The systemic gap** is that CI can only validate code that runs in CI. A database query that is fast on empty tables and slow at production scale is a class of bug that escapes most CI pipelines. Solving it properly requires either:
1. Seeding the CI database with representative data (synthetic or anonymised production)
2. Adding query plan validation (`EXPLAIN (ANALYZE, BUFFERS)`) with cardinality estimates to the CI pipeline

These are harder problems than adding a Prometheus gate, and they are being tracked as separate backlog items.

---

## Lessons

**For the team:**  
Health check probes are necessary but not sufficient as canary analysis gates. A service that responds to `/health` is alive — it may still be slow, returning degraded data, or consuming unbounded resources. Canary gates should measure what users actually experience: latency percentiles and error rates under real traffic.

**For the architecture:**  
The four-project pipeline (build → canary → observe → gate) worked. The canary contained the blast radius, the analysis detected the degradation, and the abort was automatic. The incident's root cause was a gap in one gate (health-check vs. latency), not a gap in the architecture. Fixing the gate is a targeted change that makes the whole system more robust.

**For the portfolio:**  
This incident demonstrates the value of the progressive delivery setup over "deploy to 100% and hope." If this had been a standard Kubernetes rolling update (the Project 2 behaviour), all users would have been exposed for the 14 minutes it took for the issue to be manually identified and reverted. The Argo Rollouts canary limited exposure to 20% for 4 minutes before automatic recovery.
