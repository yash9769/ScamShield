import anthropic     

client = anthropic.Anthropic(api_key="sk-peLbVI8VE5H0Dp5yfpaQC39YNUcL5yzFbhOiTZtFeyNPnGGx")

message = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1000,
    messages=[
        {"role": "user", "content": "Say hello and tell me a fun fact"}
    ]
)

print(message.content[0].text)