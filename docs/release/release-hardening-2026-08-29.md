# Release hardening status — 29 August 2026

This record separates repository-complete safeguards from external release evidence. A checked
code path is not treated as an active production control until the corresponding remote service,
credential and recovery/alert test are recorded.

## Repository safeguards

- PostgreSQL dumps remain atomic custom-format archives with a sidecar SHA-256 checksum.
- `ops/postgres/offsite.py` uploads the latest verified dump to a separate private S3-compatible
  bucket under an immutable timestamp key, verifies size/checksum metadata and maintains a
  no-cache `latest.json` recovery pointer.
- A full-download verification command hashes every downloaded byte; the restore-check command
  then restores that downloaded artifact into an isolated temporary PostgreSQL database.
- Offsite retention deletes only recognized timestamped dump/checksum keys inside the exact
  environment prefix and always preserves the active manifest target.
- Staging preflight rejects reuse of the public media bucket or its storage token for database
  backups.
- Lightweight heartbeat checks the public site, public readiness JSON and local backup freshness
  before pinging an external dead-man monitor. Missing host/network/timer heartbeats are detected
  by the external monitor rather than by the failed host itself.
- Versioned systemd service/timer templates run daily backup and five-minute heartbeat jobs with
  locks, bounded timeouts and restrictive service settings.
- `make release-check` is the single local release gate: operations tests, backend checks/tests,
  web lint/type/cache/build, both browser suites and Lighthouse.
- GitHub workflows can be triggered manually and cancel superseded runs on the same ref to avoid
  wasting Actions minutes.

## Local release evidence

- Backend: 646 passed, 6 skipped, 83.13% total coverage.
- Operations: 60 unit/configuration tests, staging configuration self-tests, shell syntax and
  Compose validation.
- Web: lint, TypeScript and five shared-cache tests passed; the production build integrity check
  passed.
- Browser: the same 80 Playwright scenarios passed against both the development server and the
  standalone production artifact.
- Lighthouse: all six localized landing/Quran routes passed their performance, accessibility,
  best-practices, SEO and transfer budgets.
- Dependency audits: npm and hash-verified production Python requirements reported no known
  vulnerabilities. Container image scanning remains an exact-commit CI gate.

## External gates still required

| Gate | Evidence required | Current state on 29 August 2026 |
|---|---|---|
| GitHub source mirror | configured remote, authenticated push and green exact-commit CI | Local `gh` credential is invalid and the repository has no remote |
| Private offsite bucket | separate bucket/token, successful upload, full download and restore | Code/preflight ready; bucket and scoped token not configured |
| Dead-man uptime monitor | success/failure URL, enabled timer and delivered test alert | Code/timer ready; external monitor URL not configured |
| Full observability delivery | deployed metrics/log backend and routed synthetic alert | Opt-in stack exists; not kept on the 4 GiB budget host |
| Quran content acceptance | provenance-safe candidate and religious/legal/product sign-offs | `madani-hafs@1.0.2` remains staging-only |
| Exact release security | GitHub dependency audits and Trivy on the release commit | Local npm/Python audits pass; container scan and exact-commit CI require GitHub authentication/remote |

## Activation sequence

1. Create a private backup bucket that is not reachable through the media custom domain. Create a
   separate token restricted to object read/write/list/delete for that bucket only.
2. Configure staging without putting credentials in shell history:

   ```bash
   make staging-backup-offsite-configure \
     STAGING_BACKUP_R2_ACCOUNT_ID=<account-id> \
     STAGING_BACKUP_R2_BUCKET=<private-backup-bucket>
   make staging-backup-offsite
   make staging-backup-offsite-verify
   make staging-backup-offsite-restore-check
   ```

3. Create a dead-man monitor with a grace period greater than the five-minute timer. Configure the
   secret URL on the host:

   ```bash
   install -d -m 0700 /etc/iqro
   python3 ops/monitoring/configure.py \
     --output /etc/iqro/staging-heartbeat.env \
     --site-url https://staging.iqro.forum \
     --backup-dir /opt/quran/backups/staging
   ```

4. Install units and enable them only after both manual commands pass:

   ```bash
   make systemd-install
   systemctl enable --now quran-backup@staging.timer quran-heartbeat@staging.timer
   systemctl start quran-backup@staging.service quran-heartbeat@staging.service
   systemctl list-timers 'quran-*'
   ```

5. Test the alert by stopping the heartbeat timer for longer than the external monitor grace
   period, confirm delivery, then re-enable it. Record the incident/test ID without storing the
   secret heartbeat URL.
6. Re-authenticate GitHub, attach the intended private repository as `origin`, push the current
   branch and run the three manual CI workflows on the exact release commit.

No external gate is marked complete merely because its implementation exists in the repository.
