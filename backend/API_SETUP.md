# 🔑 ScamShield API Configuration Guide

This guide explains how to set up and configure all external APIs used by ScamShield for enhanced threat detection capabilities.

---

## ✅ Quick Summary

| API | Required? | Cost | Purpose | Status Without Key |
|---|---|---|---|---|
| **Google Gemini** | Optional | Free tier (60 req/min) | AI-powered scam analysis | Falls back to local heuristics |
| **VirusTotal** | Optional | Free tier (600 req/day) | Detect malicious URLs | URL analysis skipped |
| **Google Safe Browsing** | Optional | Free | Check URLs against Google's database | URL checking skipped |
| **Groq** | Optional | Free tier | Fast LLM alternative to Gemini | Not used (Gemini preferred) |

**Default Behavior**: ScamShield works perfectly without any API keys. The local heuristic engine is always active and provides solid scam detection. API keys are purely optional enhancements.

---

## 1️⃣ Google Gemini (AI Analysis — Optional)

### What It Does
- Analyzes text/voice/images for scam patterns using advanced AI
- Provides detailed explanations of detected scams
- Fallback: If Gemini is unavailable or key is missing, the local heuristic engine runs instead

### How to Get a Key
1. Visit [Google AI Studio](https://aistudio.google.com/)
2. Click **"Get API Key"** (no authentication required)
3. Select or create a Google Cloud project
4. Copy your API key

### Configuration
```bash
# In backend/.env
GEMINI_API_KEY=gsk_...your_key_here...

# Or set as environment variable
export GEMINI_API_KEY=gsk_...your_key_here...
```

### Quota & Limits
- **Free Tier**: 60 requests/minute
- **Cost**: Free (rate-limited)
- **Upgrade**: Pay-as-you-go pricing available for higher volume

### Troubleshooting
- **403 Forbidden**: Key is invalid or billing is disabled. Regenerate the key in AI Studio.
- **429 Too Many Requests**: Rate limit exceeded. Space out requests or wait 60 seconds.
- **Timeout**: Gemini service is slow. Heuristic fallback activates automatically.

---

## 2️⃣ VirusTotal (URL Threat Intelligence — Optional)

### What It Does
- Checks URLs against 70+ antivirus engines
- Detects phishing, malware, and suspicious domains
- Fallback: If key is missing, URLs are analyzed using heuristics only

### How to Get a Key
1. Visit [VirusTotal](https://www.virustotal.com/)
2. Sign up for a free account
3. Go to **API** section
4. Copy your API key

### Configuration
```bash
# In backend/.env
VIRUSTOTAL_API_KEY=your_key_here...

# Or set as environment variable
export VIRUSTOTAL_API_KEY=your_key_here...
```

### Quota & Limits
- **Free Tier**: 600 requests/day (~20/hour)
- **Cost**: Free (rate-limited)
- **Upgrade**: Premium plans for higher volume

### Troubleshooting
- **401 Unauthorized**: Key is invalid. Verify in VirusTotal dashboard.
- **429 Too Many Requests**: Daily quota exhausted. Request resets at midnight UTC.
- **503 Service Unavailable**: VirusTotal service is down. Heuristics fallback works.

---

## 3️⃣ Google Safe Browsing (URL Safety — Optional)

### What It Does
- Checks URLs against Google's Safe Browsing database
- Detects phishing, malware, and unwanted software sites
- Complements VirusTotal for comprehensive URL checking

### How to Get a Key
1. Visit [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. Enable the **Safe Browsing API**
4. Create an API key (Credentials → API Keys)
5. Copy your key

### Configuration
```bash
# In backend/.env
GOOGLE_SAFE_BROWSING_API_KEY=your_key_here...

# Or set as environment variable
export GOOGLE_SAFE_BROWSING_API_KEY=your_key_here...
```

### Quota & Limits
- **Free Tier**: 10,000 requests/day
- **Cost**: Free
- **Upgrade**: Standard and Advanced tiers available

### Troubleshooting
- **403 Forbidden**: Billing not enabled. Enable in Google Cloud Console.
- **429 Too Many Requests**: Quota exhausted for the day.
- **400 Bad Request**: Ensure URL format is correct (starts with `http://` or `https://`).

---

## 4️⃣ Groq (Alternative AI — Optional)

### What It Does
- Fast LLM alternative to Google Gemini
- Can be used as a fallback if Gemini is unavailable
- Currently **not prioritized** in ScamShield (Gemini is preferred)

### How to Get a Key
1. Visit [Groq Console](https://console.groq.com/)
2. Sign up or log in
3. Create an API key
4. Copy your key

### Configuration
```bash
# In backend/.env
GROQ_API_KEY=your_key_here...

# Or set as environment variable
export GROQ_API_KEY=your_key_here...
```

### Quota & Limits
- **Free Tier**: Rate-limited (~30 req/min)
- **Cost**: Free
- **Status**: Experimental support (not used by default)

---

## 🚀 Deployment Scenarios

### Scenario 1: No API Keys (Fully Local)
**Best for**: Privacy-first deployments, offline use, self-hosted instances

```bash
# backend/.env
GEMINI_API_KEY=
VIRUSTOTAL_API_KEY=
GOOGLE_SAFE_BROWSING_API_KEY=
```

**Capabilities**:
- ✅ Text scam analysis (heuristic)
- ✅ Voice transcription & analysis
- ✅ Image OCR & analysis
- ✅ Basic URL checking
- ❌ Advanced AI analysis
- ❌ Detailed threat intel

---

### Scenario 2: Gemini Only (Recommended for Most)
**Best for**: Development, small deployments, balanced cost/benefit

```bash
# backend/.env
GEMINI_API_KEY=gsk_...
VIRUSTOTAL_API_KEY=
GOOGLE_SAFE_BROWSING_API_KEY=
```

**Capabilities**:
- ✅ Text scam analysis (AI + heuristic hybrid)
- ✅ Voice transcription & analysis
- ✅ Image OCR & analysis
- ✅ Detailed AI explanations
- ⚠️ Basic URL checking (heuristic only)

---

### Scenario 3: Full Power (Gemini + VirusTotal + Safe Browsing)
**Best for**: Production deployments, maximum threat detection

```bash
# backend/.env
GEMINI_API_KEY=gsk_...
VIRUSTOTAL_API_KEY=your_key...
GOOGLE_SAFE_BROWSING_API_KEY=your_key...
```

**Capabilities**:
- ✅ Advanced AI scam analysis
- ✅ Detailed threat intelligence
- ✅ Comprehensive URL checking (70+ engines)
- ✅ Google's phishing database
- ✅ Highest detection accuracy

**Estimated Cost**: ~$0-5/month for typical usage

---

## 🔒 Security Best Practices

1. **Never commit `.env` to version control**
   ```bash
   # .gitignore
   .env
   .env.*.local
   ```

2. **Use separate keys for different environments**
   ```bash
   # Development
   GEMINI_API_KEY=dev_key_...
   
   # Production
   GEMINI_API_KEY=prod_key_...
   ```

3. **Rotate keys regularly** (every 90 days minimum)

4. **Set API quotas / budgets** in each service's dashboard to prevent runaway costs

5. **Monitor API usage**
   ```bash
   # Docker logs
   docker-compose logs api | grep "API_ERROR\|QUOTA_EXCEEDED"
   ```

---

## 🛠️ Testing Your Configuration

### Test Gemini Connection
```bash
curl -X POST http://localhost:8000/health \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# Response should include Gemini status:
# { "status": "healthy", "services": { "gemini": "available", ... } }
```

### Test VirusTotal Connection
```bash
# Check a malicious URL (EICAR test file)
curl -X POST http://localhost:8000/osint/urls \
  -H "Content-Type: application/json" \
  -d '{"urls": ["http://www.eicar.org/eicar.com.txt"]}'
```

### Check Current Configuration
```bash
# Via logs (if ENABLE_DOCS=true)
curl http://localhost:8000/docs
# Look for available services in the UI
```

---

## ⚠️ Common Issues & Solutions

| Issue | Solution |
|---|---|
| "API key is missing or invalid" | Verify key in .env, regenerate if needed |
| Gemini gives wrong answers | Try a different prompt; Gemini accuracy varies |
| Rate limits exceeded | Spread requests over time or upgrade to paid tier |
| Service timeouts | Increase timeout in `config.py` (default: 15s for Gemini) |
| "No module named 'google.generativeai'" | Run `pip install -r requirements.txt` |

---

## 📞 Support

- **Gemini Issues**: [Google AI Studio Support](https://aistudio.google.com/)
- **VirusTotal Issues**: [VirusTotal API Docs](https://developers.virustotal.com/)
- **Safe Browsing Issues**: [Google Cloud Support](https://cloud.google.com/support)
- **ScamShield Issues**: Open a GitHub issue in the main repo

---

## 📊 Cost Analysis (Monthly Estimate)

| API | Free Tier | Typical Monthly Cost | High Volume Cost |
|---|---|---|---|
| Gemini | 60 req/min | $0 | $1-10 |
| VirusTotal | 600 req/day | $0 | $0-5 |
| Safe Browsing | 10k req/day | $0 | $0 |
| **Total** | — | **$0** | **~$5-15** |

**Recommendation**: Start with free tiers. Upgrade only if you hit rate limits or need SLA guarantees.
