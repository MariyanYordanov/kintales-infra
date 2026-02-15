# Email Setup Guide

## Strategy

We use a two-phase approach:

1. **Phase 1 (now)**: Cloudflare Email Routing — forward incoming mail, use kintales-server's Postfix container for outgoing
2. **Phase 2 (future)**: Self-hosted Postfix with DKIM/SPF/DMARC — after IP reputation builds (3-6 months)

## Why Not Direct Postfix From Day 1?

New static IP addresses often have poor reputation (previous user may have sent spam). Email from unknown IPs frequently lands in spam folders. Starting with Cloudflare Email Routing:

- Guarantees incoming mail works immediately
- Outgoing mail from kintales-server's Postfix works for transactional email (password resets, notifications) because volume is low
- Gives your IP time to build reputation
- Lets you set up SPF/DKIM/DMARC records gradually

## Phase 1: Cloudflare Email Routing

### Setup Steps

1. **Log into Cloudflare Dashboard** → select kintales.net
2. **Go to Email → Email Routing**
3. **Enable Email Routing** → follow the setup wizard
4. **Add destination address**: your personal email (e.g. admin@gmail.com)
5. **Verify destination** (Cloudflare sends verification email)
6. **Create routing rules**:
   - `admin@kintales.net` → your personal email
   - `*@kintales.net` (catch-all) → your personal email

Cloudflare automatically creates the required DNS records:
- MX records pointing to Cloudflare
- TXT record for SPF

### DNS Records (Auto-Created by Cloudflare)

| Type | Name | Content |
|------|------|---------|
| MX | kintales.net | `route1.mx.cloudflare.net` (priority 69) |
| MX | kintales.net | `route2.mx.cloudflare.net` (priority 32) |
| MX | kintales.net | `route3.mx.cloudflare.net` (priority 90) |
| TXT | kintales.net | `v=spf1 include:_spf.mx.cloudflare.net ~all` |

### Additional SPF for Outgoing Mail

Since kintales-server's Postfix sends outgoing mail directly, update the SPF record to include your IP:

```
v=spf1 ip4:[STATIC_IP] include:_spf.mx.cloudflare.net ~all
```

### Verify

1. Send email TO `admin@kintales.net` → should arrive at your personal email
2. Check headers for Cloudflare routing confirmation
3. Send test email FROM kintales-server: `bash /path/to/kintales-server/postfix/test-email.sh admin@gmail.com`
4. Check: email arrives (may be in spam initially — that's OK)

## Phase 2: Migration to Self-Hosted Postfix

### When to Migrate

Migrate when ALL conditions are met:
- IP has been active for 3+ months
- SPF, DKIM, and DMARC records are configured
- Test emails consistently land in inbox (not spam)
- mail-tester.com score is 9+/10

### Migration Steps

See `postfix/` directory for all configuration files:
1. Generate DKIM keys: `bash postfix/opendkim/generate-dkim.sh`
2. Add DNS records (see `postfix/opendkim/README.md`)
3. Update MX records to point to your server
4. Remove Cloudflare Email Routing
5. Test: `bash postfix/test-email.sh admin@gmail.com`
6. Verify at https://www.mail-tester.com/

## Troubleshooting

### Outgoing email lands in spam
- Check SPF: `dig TXT kintales.net` — should include your IP
- Check IP reputation: https://www.barracudacentral.org/lookups
- Consider using a relay service (Mailgun, SendGrid free tier) temporarily
- Volume matters: send legitimate email consistently to build reputation

### Cloudflare Email Routing not working
- Check MX records: `dig MX kintales.net`
- Verify destination email is confirmed in Cloudflare
- Check Cloudflare Email Routing dashboard for errors

### No email received at all
- Check DNS propagation: `dig MX kintales.net @8.8.8.8`
- Wait 24-48 hours for full DNS propagation
- Test with different sender (Gmail, Outlook, etc.)
