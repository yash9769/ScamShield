"""Regression tests for the heuristic (no-AI-key) scam detector.

Each message below was misclassified before the rules for OTP requests,
service-disconnection threats and upfront fees were added, or is a genuine
message that must stay "safe" (a bank OTP with its "do not share" warning,
text containing "shipping" or "window").
"""

import os

import pytest

os.environ.setdefault("ADMIN_API_KEY", "test-admin-key")

import main  # noqa: E402

SCAMS = [
    "URGENT: Your SBI account is blocked. Update KYC now at http://sbi-kyc-update.top/login or it will be suspended. Share OTP 482913 with our agent.",
    "Congratulations! You won Rs 25,00,000 in KBC lottery. Pay Rs 5000 processing fee to claim.",
    "Dear customer your electricity will be disconnected tonight. Call 9876543210 immediately and pay Rs 10 via the link",
    "Your SIM will be deactivated within 24 hours due to incomplete KYC. Call 7003123456 now.",
    "Your parcel is held at customs. Pay customs charges of Rs 299 at http://bit.ly/parcel-fee to release it.",
    "Earn Rs 5000 daily working from home! Guaranteed returns, just pay Rs 500 registration fee to start.",
    "Hi this is the bank executive, please tell me the code you just received to stop the fraud transaction.",
    "Income tax refund of Rs 15,490 approved. Verify your account at http://incometax-refund.xyz to receive it.",
    "Your Netflix payment failed. Update your billing details at http://netflix-billing-help.top within 24 hours or your account will be suspended.",
    "Dear user, your PAN card is blocked. Click here to update: http://pan-update.info",
]

GENUINE = [
    "Hi Priya, are we still on for lunch at 1pm tomorrow? I will book the table.",
    "Your Amazon order 402-118 has shipped and arrives Thursday.",
    "Your OTP for HDFC netbanking login is 551203. Do not share it with anyone. Valid for 5 minutes.",
    "123456 is your WhatsApp code. Never share this code.",
    "Rs 2,340 debited from A/c XX4521 on 21-Oct via UPI to Zomato. Not you? Call 1800-202-6161.",
    "Your electricity bill of Rs 1,240 for October is generated. Due date 5 Nov. Pay via the official app.",
    "Meeting moved to 4pm, open the window in the conference room, it's stuffy.",
    "Your shipping label is ready. Pickup tomorrow between 10am and 2pm.",
    "Congratulations on your promotion! Let's celebrate this weekend.",
    "Reminder: your dentist appointment is on Monday at 11:30.",
]


@pytest.mark.parametrize("text", SCAMS)
def test_scams_are_flagged(text):
    assert main.heuristic_analyze(text).classification.value != "safe"


@pytest.mark.parametrize("text", GENUINE)
def test_genuine_messages_stay_safe(text):
    assert main.heuristic_analyze(text).classification.value == "safe"


def test_otp_request_vs_delivery():
    assert main._asks_for_otp("Share OTP 482913 with our agent")
    assert main._asks_for_otp("please tell me the code you just received")
    assert not main._asks_for_otp("Your OTP is 551203. Do not share it with anyone.")
    assert not main._asks_for_otp("123456 is your WhatsApp code. Never share this code.")


def test_keywords_match_whole_words_only():
    assert main._keyword_hits(["pin", "win"], "your shipping window") == []
    assert main._keyword_hits(["pin"], "enter your pin now") == ["pin"]
