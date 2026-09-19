# Putting the dashboard online with Cloudflare

Reaching `ema_report.py --serve` from your phone or any browser, with Google
sign-in in front of it, without opening a single port on the MT5 VPS.

The tunnel **dials out** from the VPS to Cloudflare. Nothing connects inward, so
there is no port to scan and no firewall rule to add. Sign-in is enforced by
Cloudflare before the request ever reaches your machine.

Assumes a Windows VPS running MT5. Linux is the same flow with different paths.

---

## Before you start

- [ ] The dashboard runs locally on the VPS and you can open `http://localhost:8800`
- [ ] A domain you control (a Hostinger domain is fine)
- [ ] A free Cloudflare account

Start the dashboard bound to localhost — this stays true for every step below:

```bat
python ema_report.py "C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hash>\MQL5\Files\*.jsonl" --serve 8800 --poll 5
```

> Leave it on `127.0.0.1` (the default). Never use `--host 0.0.0.0`. The tunnel
> reaches the dashboard from inside the machine, so the port never needs to be
> exposed — and an exposed port gets found by scanners within hours.

---

## Part A — a 2-minute look, no domain needed

Worth doing first. It proves the dashboard works through a tunnel before you
involve DNS.

1. Install cloudflared:
   ```bat
   winget install --id Cloudflare.cloudflared
   ```
   Or download `cloudflared-windows-amd64.exe` from Cloudflare's cloudflared
   releases page and put it somewhere on your `PATH`.

2. With the dashboard already running, open a second terminal:
   ```bat
   cloudflared tunnel --url http://localhost:8800
   ```

3. It prints a `https://<random-words>.trycloudflare.com` URL. Open it on your
   phone. That is the dashboard.

**Stop here for anything permanent.** That URL has *no authentication* — anyone
who has it sees your balance, equity and open positions — and it changes every
time you restart. It is a test, not a deployment.

Ctrl-C when you are done looking.

---

## Part B — a permanent tunnel

Two ways to do this. **Take the first one on Windows.** The CLI route puts a
config file and a credentials file in your user profile, but the Windows service
runs as `LocalSystem` and looks somewhere else entirely — it is the single most
common way this setup breaks.

### B1 — dashboard-managed (recommended)

1. Add your domain to Cloudflare: **Cloudflare dashboard → Add a site**. It
   gives you two nameservers.

2. Point the domain at them. In hPanel: **Domains → your domain → DNS /
   Nameservers → Change nameservers → Use custom nameservers**, paste
   Cloudflare's two, save. Propagation is usually minutes, occasionally hours.
   Wait until Cloudflare shows the site as **Active**.

3. Go to **Cloudflare Zero Trust** (`one.dash.cloudflare.com`) →
   **Networks → Tunnels → Create a tunnel** → **Cloudflared** → name it `ea`.

4. It shows an install command containing a long token. Copy the **Windows**
   one and run it on the VPS in an **Administrator** terminal. It looks like:
   ```bat
   cloudflared.exe service install eyJhIjoi...
   ```
   That one command installs cloudflared as a Windows service, registers it,
   and starts it. No config file, no credentials path to get wrong.

5. Back in the tunnel's **Public Hostname** tab → **Add a public hostname**:

   | Field | Value |
   |---|---|
   | Subdomain | `ea` |
   | Domain | `yourdomain.com` |
   | Type | `HTTP` |
   | URL | `localhost:8800` |

   Save. `https://ea.yourdomain.com` now reaches the dashboard — and the DNS
   record is created for you.

6. Confirm the tunnel shows **Healthy** in the Tunnels list.

> `HTTP` and `localhost:8800` are correct here — the hop from cloudflared to
> Python is inside the machine. The public side is HTTPS regardless.

### B2 — CLI-managed (Linux, or if you prefer files)

```bash
cloudflared tunnel login                       # browser opens, pick the domain
cloudflared tunnel create ea                   # writes <tunnel-id>.json
cloudflared tunnel route dns ea ea.yourdomain.com
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: ea
credentials-file: /root/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: ea.yourdomain.com
    service: http://localhost:8800
  - service: http_status:404
```

The bare `service: http_status:404` at the end is required — a config without a
catch-all rule is rejected.

```bash
cloudflared tunnel run ea          # test in the foreground
sudo cloudflared service install   # then install it
```

On Windows this is where it bites: copy `config.yml` **and** the credentials
JSON into `C:\Windows\System32\config\systemprofile\.cloudflared\` before
installing the service, or it will start and find nothing.

---

## Part C — the sign-in

Right now the URL is public. This is the step that matters.

1. **Zero Trust → Access → Applications → Add an application → Self-hosted**

2. Application configuration:

   | Field | Value |
   |---|---|
   | Application name | `EA dashboard` |
   | Session duration | **24 hours** or longer — see the note below |
   | Subdomain / domain | `ea` / `yourdomain.com` |

3. Add a policy:

   | Field | Value |
   |---|---|
   | Policy name | `me only` |
   | Action | **Allow** |
   | Include → selector | **Emails** |
   | Value | your email address |

4. Login methods: **One-time PIN** works immediately with no setup — Cloudflare
   emails you a code. To use Google instead, add it under **Settings →
   Authentication → Login methods** first.

5. Save, then open `https://ea.yourdomain.com` in a private window. You should
   get a Cloudflare login screen, not the dashboard.

> **Set a long session duration.** The page polls `/live.json` every few seconds.
> When an Access session expires, those polls are redirected to the login screen,
> the fetch fails, and the indicator sits on "reconnecting" until you reload and
> sign in again. A short session turns a live dashboard into a nag. 24 hours or
> a week is reasonable for a single-user tool.

---

## Part D — surviving a reboot

The tunnel is already a service after Part B. The dashboard is not — and a VPS
that reboots overnight leaves you with a healthy tunnel pointing at nothing.

**Task Scheduler → Create Task** (not "Basic Task"):

- **General** → *Run whether user is logged on or not*, and tick *Run with
  highest privileges*
- **Triggers** → New → *At startup*
- **Actions** → New → Start a program:
  - Program: `C:\Path\To\python.exe`
  - Arguments: `ema_report.py "C:\...\MQL5\Files\*.jsonl" --serve 8800 --poll 5`
  - Start in: the folder holding `ema_report.py` — **do not leave this blank**
- **Settings** → tick *If the task fails, restart every 1 minute*, and untick
  *Stop the task if it runs longer than...*

Reboot the VPS once and confirm the dashboard comes back on its own. It is the
only way to know this worked.

The dashboard comes back on its own after a reboot; **MT5 does not**, unless
Windows is set to log itself in. That, and what an unplanned restart does to an
open trade, is in **[RESTART_RECOVERY.md](RESTART_RECOVERY.md)**.

---

## Checking it actually works

| Test | Expected |
|---|---|
| `https://ea.yourdomain.com` in a private window | Cloudflare login, then the dashboard |
| Zero Trust → Networks → Tunnels | `ea` shows **Healthy** |
| A different email at the login | Refused |
| Phone, off wifi, mobile data | Works |
| Leave it open 5 minutes | Header dot stays green, freshness badge keeps updating |
| Reboot the VPS | Everything returns without you logging in |

---

## When it does not work

**"Tunnel is healthy" but the page 502s.** cloudflared is up and Python is not.
Check `http://localhost:8800` on the VPS itself.

**Page loads, dot says "reconnecting".** The polls are failing while the page
itself loaded. Almost always an expired Access session — reload and sign in, then
lengthen the session duration. If it persists, open the browser's Network tab and
look at `live.json`: a `302` confirms Access, a `403` means you are serving with
`--token` and the token is missing from the URL.

**The service starts then stops (CLI route, Windows).** The config and
credentials are not where `LocalSystem` looks. See the end of B2, or redo it the
B1 way.

**Cloudflare never shows the site as Active.** The nameserver change has not
propagated, or hPanel silently kept the old ones. Re-check in hPanel.

**Login loops without ever landing.** Third-party cookies blocked, or the
application domain does not exactly match the hostname you are opening.

---

## Worth keeping in mind

- This dashboard is **read-only**. Nobody can place, change or close a trade
  through it. That keeps the risk to disclosure — balance, equity, lot sizes —
  rather than execution.
- If you would rather not put money figures on the internet at all, add `--anon`.
  R multiples, win rate, profit factor and the session and filter breakdowns all
  survive; cash and balances are dropped, not blanked.
- An unguessable URL is **not** access control. Unlinked URLs leak through
  browser telemetry, extensions, screenshots and certificate transparency logs.
  Part C is the part that protects you, not the randomness of the hostname.
- Never expose RDP on the MT5 VPS either. Same reasoning, much worse outcome.
- Cloudflare's dashboard labels move around between redesigns. If a menu name
  here does not match what you see, the shape of the task is still right:
  create a tunnel, give it a public hostname, put an Access application in
  front of that hostname.
