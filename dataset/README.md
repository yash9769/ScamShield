# ScamShield Dataset Card

## Overview
This dataset contains **200 labelled messages** (100 scam, 100 safe) collected and curated for training and evaluation of the ScamShield scam detection system.

## Dataset Statistics

| Split | Count | Classes |
|-------|-------|---------|
| Scam messages | 100 | smishing, phishing, vishing, lottery, job, investment, otp, romance, tech_support, financial |
| Safe messages | 100 | banking, ecommerce, personal, work, utility, education, reminder, social |
| **Total** | **200** | — |

## Files

| File | Description |
|------|-------------|
| `scam_messages.csv` | 100 labelled scam messages |
| `safe_messages.csv` | 100 labelled safe messages |
| `evaluation/evaluation_report.md` | Full evaluation metrics |

## Schema

```
id        - Unique integer ID
message   - The text message content
label     - 'scam' or 'safe'
category  - Sub-category of the message type
```

## Collection Methodology
- Scam messages: Synthesised representative examples modelled after documented Indian cybercrime patterns (smishing, vishing, phishing, lottery, job, investment fraud). No real victim PII is included.
- Safe messages: Representative examples of legitimate transactional, informational, and personal messages from common Indian services (HDFC, SBI, Flipkart, Amazon, IRCTC, etc.).

## Label Schema

### Scam Categories
| Category | Description |
|----------|-------------|
| `smishing` | SMS-based phishing targeting mobile users |
| `phishing` | Link/URL-based credential theft |
| `vishing` | Voice/phone impersonation scams |
| `lottery` | Fake prize/lottery advance fee fraud |
| `job` | Fraudulent job/work-from-home offers |
| `investment` | Ponzi, crypto, MLM investment scams |
| `otp` | OTP solicitation fraud |
| `romance` | Romance scam patterns |
| `tech_support` | Fake technical support scams |
| `financial` | General financial fraud patterns |

### Safe Categories
| Category | Description |
|----------|-------------|
| `banking` | Legitimate bank/financial service notifications |
| `ecommerce` | Order/delivery/refund notifications |
| `personal` | Personal interpersonal messages |
| `work` | Professional/workplace communications |
| `utility` | Bills, utilities, government services |
| `education` | Academic/institutional messages |
| `reminder` | Appointment/renewal reminders |
| `social` | Social media and networking |

## Usage
This dataset is used for:
1. **Local detector validation** — Testing the `ScamDetector` keyword-heuristic engine
2. **Evaluation** — Computing accuracy, precision, recall, F1 score, and confusion matrix
3. **Future ML training** — Training a fine-tuned NLP model for improved detection

## Limitations
- Messages are representative examples, not real user data
- English/Hinglish mix; multilingual support (Hindi, Marathi) not yet included
- Rapidly evolving scam tactics may not be covered
