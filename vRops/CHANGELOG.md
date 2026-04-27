# Invoke-VROpsAdapterHealthCheck — Changelog

---

## Recent Changes

### Certificate Acceptance — Corrected API Flow
**The biggest fix.** Certificate acceptance was originally done via `PUT /suite-api/api/adapters/{id}`, which consistently failed with HTTP 422 or silently only accepted the last certificate when multiple were present.

The correct documented pattern is:
1. `POST /suite-api/api/adapters/testconnection` — test the connection, receive the response including any `adapter-certificates`
2. `PATCH /suite-api/api/adapters/testconnection` — send that **entire POST response body back as-is** to mark the certificates as trusted
3. Re-run the `POST` to confirm the connection now succeeds

This is handled inside `Test-VROpsAdapterConnection -AcceptCertificate` in the `VROps-Custom` module. The script calls this for both the interactive (Y/Accept All) and non-interactive (`-AcceptCerts`) paths.

---

### Multiple Certificates Per Adapter
Previously only the last certificate thumbprint was being accepted when an adapter returned multiple certs (e.g. NSX-T adapters commonly return 4). The original loop was overwriting `$body['certificateThumbprint']` on each iteration before the PATCH was sent.

Fixed by collecting all thumbprints from the `adapter-certificates` response array and including them together before the PATCH call.

---

### HTTP 422 on PUT /adapters — collectorId Conflict
When attempting cert acceptance via PUT (now replaced — see above), the API returned:
```
Either 'collectorId' or 'collectorGroupId' should be specified but not both.
```
The GET response for an adapter includes both fields populated. The PUT requires exactly one. This was fixed by stripping `collectorId` from the body when `collectorGroupId` is present. This fix remains in `Confirm-VROpsAdapterCertificate` for any direct use of that function outside the script.

---

### Connection Prompt — Ping Check + Credential Retry
If no active `Connect-OMServer` session exists when the script runs, it now:
1. Prompts for a hostname and runs `Test-Connection` before attempting to connect — loops if unreachable
2. Prompts for credentials via `Get-Credential`
3. Catches authentication failures from `Connect-OMServer` and re-prompts rather than terminating

---

### Interactive Adapter Selection Menu
Rather than requiring adapter kind keys to be known upfront, the script retrieves all adapter instances, groups them by `adapterKindKey`, and presents a numbered list. Input accepts comma-separated numbers (e.g. `1,3,9`), `A` for all, or `Q` to quit. The `-Adapters` parameter still works for non-interactive/automation use.

---

### Stopped/Disabled Adapter Filtering
Adapters in `NOT_COLLECTING` or `DISABLED` collection state are skipped by default. Use `-IncludeStopped` to include them.

---

### CSV Logging
If `-LogPath` is not provided, the script prompts whether to log results. Defaults to a timestamped CSV in the same directory as the script. Results include adapter name, kind, ID, test result, cert action taken, and any error message.
