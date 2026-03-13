from fastapi import FastAPI, Request
import uvicorn
import json

app = FastAPI()

@app.get("/v1/models")
async def models():
    print("GET /v1/models")
    return {
        "object": "list",
        "data": [
            {"id": "gpt-4o", "object": "model"}
        ]
    }

@app.post("/v1/chat/completions")
async def chat(req: Request):
    data = await req.json()
    print("\n==== REQUEST ====")
    print(json.dumps(data, indent=2))

    return {
        "id": "chatcmpl-test",
        "object": "chat.completion",
        "model": "gpt-4o",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": "ok"},
                "finish_reason": "stop"
            }
        ]
    }

uvicorn.run(app, host="0.0.0.0", port=8000)