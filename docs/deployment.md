# Academy server deployment

Use an always-on academy-controlled Ubuntu server with reliable connectivity, SSD storage, and a backup destination on a separate private device. GitHub Pages is the public frontend. It does not host the API or database.

## Backend service

1. Install Python 3.12, Docker, Compose, and GnuPG. Create a dedicated `quranacademy` operating-system user. Place a reviewed checkout at `/srv/al-hassan`; install the backend virtual environment there.
2. Set server-owned secrets in `backend/.env` with mode `0600`. Use a dedicated PostgreSQL account and database, and retain the local-only database port binding. Configure `ACADEMY_ORIGINS=https://arshadqais.github.io`.
3. Start PostgreSQL using `infra/compose.yaml`, using the same password as the API. Back up the database before running migrations. Run `python -m alembic upgrade head` from `backend` and bootstrap an administrator with `python -m app.manage create-admin`.
4. Adapt and review `infra/al-hassan-api.service` for the actual paths and user. Install/enable it through systemd on that server. The example listens only on `127.0.0.1:8000` and uses a single worker because the pilot login limiter is process-local.
5. Configure the academy's authenticated HTTPS reverse proxy or Cloudflare Tunnel to route the API domain to that local service. Terminate TLS with a valid certificate. Set request-size limits and edge rate limits; only trust forwarded client headers from the proxy you control. Do not publish PostgreSQL or expose the server management interface.
6. Check `/health/db` externally, sign in with each role, and verify object ownership using separate test users before enrollment. Add `ACADEMY_API_BASE_URL` to GitHub repository variables and redeploy the frontend.

Secrets stay on the server. The frontend API base URL is public configuration. Cloud proxy placeholders cannot sign local JWTs; LiveKit signing credentials must be real server-side runtime values, entered securely by the operator.

## Private classrooms

Create a LiveKit project or self-host an appropriately configured LiveKit service. Configure `LIVEKIT_URL` as its `wss://` URL, and set `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` only on the backend. Restart the API after updating its environment.

The token endpoint first checks role and enrollment. It issues a ten-minute grant for one class room, never a general administrator grant. The room opens 15 minutes before a lesson and closes to new joins 30 minutes after the scheduled end. Students can publish camera/microphone; only teachers and administrators get screen-sharing grants. Parents cannot enter rooms through the token endpoint. Microphone and camera are initially off in the browser, and each requires user activation and browser permission. Recording controls are not implemented.

Validate teacher/student audio, camera, screen sharing, leaving/rejoining, denied browser permissions, unsupported mobile screen sharing, and unrelated-user denial against the actual provider. Provider network/firewall and browser restrictions must be checked from the devices that will teach and attend classes. No successful real media call has been claimed from a token unit test.

## Backups and recovery

`infra/scripts/backup.sh` makes a PostgreSQL custom-format dump, encrypts it with GnuPG AES-256 and an integrity check, and writes only the completed encrypted archive. It refuses to overwrite an existing archive for the same timestamp. Provide `BACKUP_PASSPHRASE` securely through the server scheduler environment; do not put it in source, shell history, or the backup folder.

```bash
bash infra/scripts/backup.sh /private/academy-backups
```

Copy the resulting `.dump.gpg` archive to an access-controlled off-machine destination using your selected secure backup service. Store the recovery passphrase separately. Set a retention policy and monitor successful backups. The script does not configure remote storage automatically.

For a restore drill, use a **separate test database**, decrypt with GnuPG, and pipe the dump to `pg_restore`. Restore application data only during a planned recovery with a separate preserved backup. Never restore over a running production database as a test. The development validation encrypted an empty pilot-schema dump and restored it into an isolated PostgreSQL database; it did not test your future storage account, retention, or remote restore process.

Resource files need an additional backup strategy when file uploads are implemented. Current resources are text study notes stored in PostgreSQL, so they are included in the database dump.

## Releases and rollback

For each backend release, keep the previous checkout/build, an encrypted database backup, and the migration revision. Run tests before deploying. Stop writes, back up, apply migrations, restart the API, and verify login plus a representative student/teacher/parent workflow. On a failed release, restore the previous application version; database downgrades require reviewing the migration and the data loss consequences. Restore a database backup only as an explicit recovery action.

The included initial migration has a destructive downgrade. It is for a new pilot schema, not a routine production rollback plan. More schema changes need reviewed migrations.

## Remaining operational work

Use academy-owned domain, hosting and LiveKit accounts. Add external rate limiting, monitoring, session cleanup, password recovery, consent rules, and retention policy before broad use. Configure and exercise off-machine backup recovery. There is no unattended deployment channel into an academy machine in the GitHub workflow.
