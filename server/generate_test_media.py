import os
import wave
import math
import struct
from PIL import Image, ImageDraw, ImageFont

# 1. Generate PNG image with text
img = Image.new("RGB", (600, 200), color=(15, 23, 42))
d = ImageDraw.Draw(img)
d.text((20, 50), "URGENT ALERT: Bank account locked!", fill=(239, 68, 68))
d.text((20, 100), "Verify details immediately at http://bit.ly/scam-bank-login", fill=(6, 182, 212))
img.save("../QA/test-data/images/sample_scam_screenshot.png")
print("Saved sample_scam_screenshot.png OK.")

# 2. Generate clean WAV audio file
wav_path = "../QA/test-data/audio/sample_voice_note.wav"
with wave.open(wav_path, "w") as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(16000)
    for i in range(16000): # 1 second 440Hz sine wave tone
        sample = int(32767.0 * math.sin(2.0 * math.pi * 440.0 * i / 16000))
        wf.writeframes(struct.pack("<h", sample))
print("Saved sample_voice_note.wav OK.")
