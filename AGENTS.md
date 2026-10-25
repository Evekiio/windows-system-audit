# Agent instructions

## Manual change delivery — owner direction, October 25, 2026

- Inspect Git status first and preserve unrelated work. Make focused changes on a feature branch; never force-push or bypass branch protections.
- Use meaningful commits and a draft pull request to `main`. Perform appropriate local validation, record commands/results and limitations in the PR, mark it ready, then merge normally when the applicable checks/protections allow. A separate reviewer is not currently required by the owner; existing required checks and security boundaries still apply.
- Do not rely on GitHub Actions or automatic dependency PRs as the delivery process. Do not add or re-enable workflows, scheduled updaters, auto-merge bots or other automation without explicit owner direction. Existing security or publication automation must remain until its specific removal/replacement is authorized.
- Review dependencies manually: assess advisories, compatibility and the active dependency inputs, then make a scoped, validated PR. Never rewrite immutable historical editions or archived release artifacts to silence updater findings.
- Keep security scanning, vulnerability alerts, push protection, required security checks and other security controls intact unless the owner explicitly approves the exact change. Manual delivery is not permission to weaken security.
- Distinguish local checks, reviewed external evidence and unverified acceptance. Do not report tests as run when only reading old CI results. Preserve product-specific limits on live hardware, installation, deployment, release approval and human acceptance.
