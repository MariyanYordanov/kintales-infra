# DKIM / SPF / DMARC Setup

## Overview

These three technologies work together to prove that emails from kintales.net are legitimate:

- **SPF** (Sender Policy Framework): "Only these IP addresses can send mail for kintales.net"
- **DKIM** (DomainKeys Identified Mail): "This email has a cryptographic signature from kintales.net"
- **DMARC** (Domain-based Message Authentication): "If SPF or DKIM fails, reject the email"

## Step 1: Generate DKIM Keys

```bash
bash postfix/opendkim/generate-dkim.sh kintales.net
```

This creates:
- `keys/mail.private` — private key (stays on server)
- `keys/mail.txt` — public key (goes in DNS)

## Step 2: Add DNS Records in Cloudflare

### DKIM Record (TXT)
| Field | Value |
|-------|-------|
| Type | TXT |
| Name | `mail._domainkey.kintales.net` |
| Content | `v=DKIM1; k=rsa; p=[PUBLIC_KEY_FROM_STEP_1]` |

### SPF Record (TXT)
| Field | Value |
|-------|-------|
| Type | TXT |
| Name | `kintales.net` |
| Content | `v=spf1 ip4:[STATIC_IP] -all` |

### DMARC Record (TXT)
| Field | Value |
|-------|-------|
| Type | TXT |
| Name | `_dmarc.kintales.net` |
| Content | `v=DMARC1; p=reject; rua=mailto:admin@kintales.net` |

### MX Record
| Field | Value |
|-------|-------|
| Type | MX |
| Name | `kintales.net` |
| Content | `mail.kintales.net` |
| Priority | 10 |

### Mail A Record
| Field | Value |
|-------|-------|
| Type | A |
| Name | `mail.kintales.net` |
| Content | `[STATIC_IP]` |

## Step 3: Verify

```bash
# Check DKIM
dig TXT mail._domainkey.kintales.net

# Check SPF
dig TXT kintales.net

# Check DMARC
dig TXT _dmarc.kintales.net

# Check MX
dig MX kintales.net

# Send test email
bash postfix/test-email.sh your@gmail.com
```

## Step 4: Test with mail-tester.com

1. Go to https://www.mail-tester.com/
2. Copy the temporary email address shown
3. Send a test email to that address from your server
4. Check your score (target: 9+/10)

## Troubleshooting

### Email in spam
- Check IP reputation: https://www.barracudacentral.org/lookups
- Verify SPF includes your IP: `dig TXT kintales.net`
- Verify DKIM is valid: check email headers in Gmail ("signed-by: kintales.net")
- Check DMARC: look for "dmarc=pass" in email headers

### DKIM signature invalid
- Verify public key in DNS matches generated key
- Check OpenDKIM is running: `docker exec postfix opendkim -t`
- Check milter connection: `postconf smtpd_milters`
