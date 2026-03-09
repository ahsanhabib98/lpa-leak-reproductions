from __future__ import annotations

import json
import os
import socketserver
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

import psutil
import requests

# Configuration

UPSTREAM_BIND_HOST = os.getenv("UPSTREAM_BIND_HOST", "0.0.0.0")
UPSTREAM_DISPLAY_HOST = os.getenv("UPSTREAM_DISPLAY_HOST", "127.0.0.1")
UPSTREAM_PORT = int(os.getenv("UPSTREAM_PORT", "9000"))

NEXTCHAT_URL = os.getenv(
    "NEXTCHAT_URL",
    "http://127.0.0.1:3000/api/openai/v1/chat/completions",
)

CONCURRENT_CLIENTS = int(os.getenv("CONCURRENT_CLIENTS", "100"))
SPAWN_INTERVAL_SEC = float(os.getenv("SPAWN_INTERVAL_SEC", "0.05"))
REPORT_EVERY_SEC = float(os.getenv("REPORT_EVERY_SEC", "5"))
CLIENT_TIMEOUT_SEC = int(os.getenv("CLIENT_TIMEOUT_SEC", str(60 * 60)))

NEXTCHAT_PID = os.getenv("NEXTCHAT_PID")
NEXTCHAT_PID = int(NEXTCHAT_PID) if NEXTCHAT_PID else None

DOCKER_CONTAINER = os.getenv("DOCKER_CONTAINER", "chatgpt-next-web").strip()

SIMULATE_CLIENT_DISCONNECT = os.getenv("SIMULATE_CLIENT_DISCONNECT", "0") == "1"
CLIENT_DISCONNECT_AFTER_SEC = int(os.getenv("CLIENT_DISCONNECT_AFTER_SEC", "5"))

ACCESS_CODE = os.getenv("ACCESS_CODE", "").strip()
EXTRA_HEADERS_JSON = os.getenv("EXTRA_HEADERS_JSON", "").strip()

# Global counters

stop_event = threading.Event()
active_sessions: list[requests.Session] = []

started_requests = 0
failed_requests = 0
success_200 = 0
forbidden_403 = 0
other_non_200 = 0

upstream_hits = 0
upstream_streams_opened = 0
upstream_broken_pipes = 0

counter_lock = threading.Lock()


# Helpers

def read_http_body(handler: BaseHTTPRequestHandler) -> bytes:
    transfer_encoding = handler.headers.get("Transfer-Encoding", "").lower()
    content_length = handler.headers.get("Content-Length")

    if "chunked" in transfer_encoding:
        chunks: list[bytes] = []

        while True:
            line = handler.rfile.readline()
            if not line:
                break

            line = line.strip()
            if not line:
                continue

            try:
                chunk_size = int(line.split(b";")[0], 16)
            except ValueError:
                break

            if chunk_size == 0:
                while True:
                    trailer = handler.rfile.readline()
                    if not trailer or trailer in (b"\r\n", b"\n"):
                        break
                break

            chunk = handler.rfile.read(chunk_size)
            chunks.append(chunk)

            handler.rfile.read(2)

        return b"".join(chunks)

    if content_length:
        try:
            length = int(content_length)
            return handler.rfile.read(length) if length > 0 else b""
        except Exception:
            return b""

    return b""


def build_headers() -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer test",
    }

    if ACCESS_CODE:
        headers["x-access-code"] = ACCESS_CODE
        headers["access-code"] = ACCESS_CODE

    if EXTRA_HEADERS_JSON:
        try:
            extra = json.loads(EXTRA_HEADERS_JSON)
            if isinstance(extra, dict):
                headers.update({str(k): str(v) for k, v in extra.items()})
        except Exception as e:
            print(f"[warn] Could not parse EXTRA_HEADERS_JSON: {e}")

    return headers


def docker_mem_stats(container_name: str) -> str | None:
    if not container_name:
        return None
    try:
        out = subprocess.check_output(
            ["docker", "stats", "--no-stream", "--format", "{{.MemUsage}}", container_name],
            stderr=subprocess.STDOUT,
            text=True,
        ).strip()
        return out or None
    except Exception:
        return None


def find_nextchat_pid() -> int | None:
    global NEXTCHAT_PID

    if NEXTCHAT_PID is not None:
        return NEXTCHAT_PID

    candidates = []
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            cmdline = " ".join(proc.info.get("cmdline") or [])
            name = proc.info.get("name") or ""
            cmdline_l = cmdline.lower()
            name_l = name.lower()

            if (
                "next start" in cmdline_l
                or "next-server" in cmdline_l
                or "chatgpt-next-web" in cmdline_l
                or ("node" in name_l and "next" in cmdline_l)
            ):
                candidates.append(proc.info["pid"])
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    if candidates:
        NEXTCHAT_PID = candidates[0]
        return NEXTCHAT_PID

    return None


def process_stats(pid: int) -> dict:
    try:
        proc = psutil.Process(pid)
        mem = proc.memory_info()

        try:
            conns = proc.net_connections(kind="inet")
            num_connections = len(conns)
        except Exception as e:
            num_connections = -1
            conn_error = repr(e)
        else:
            conn_error = None

        try:
            threads = proc.num_threads()
        except Exception as e:
            return {"error": f"num_threads failed: {repr(e)}"}

        out = {
            "rss_mb": mem.rss / 1024 / 1024,
            "vms_mb": mem.vms / 1024 / 1024,
            "num_connections": num_connections,
            "num_threads": threads,
        }
        if conn_error:
            out["conn_error"] = conn_error
        return out
    except Exception as e:
        return {"error": repr(e)}


# Fake OpenAI upstream

class HangingOpenAIHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stdout.write("[upstream] " + (fmt % args) + "\n")
        sys.stdout.flush()

    def do_POST(self):
        global upstream_hits, upstream_streams_opened, upstream_broken_pipes

        parsed = urlparse(self.path)
        path = parsed.path

        with counter_lock:
            upstream_hits += 1

        if path != "/v1/chat/completions":
            body = b'{"error":"not found"}'
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            return

        body = read_http_body(self)

        try:
            payload = json.loads(body.decode("utf-8", errors="replace") or "{}")
        except Exception:
            payload = {}

        stream = payload.get("stream", False)

        if stream:
            with counter_lock:
                upstream_streams_opened += 1

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            try:
                self.wfile.write(
                    b'data: {"id":"fake-1","choices":[{"delta":{"role":"assistant"}}]}\n\n'
                )
                self.wfile.flush()
            except Exception:
                with counter_lock:
                    upstream_broken_pipes += 1
                return

            counter = 0
            while not stop_event.is_set():
                counter += 1
                chunk = {
                    "id": f"fake-{counter}",
                    "choices": [{"delta": {"content": "."}}],
                }
                data = f"data: {json.dumps(chunk)}\n\n".encode("utf-8")

                try:
                    self.wfile.write(data)
                    self.wfile.flush()
                except Exception:
                    with counter_lock:
                        upstream_broken_pipes += 1
                    break

                time.sleep(30)

        else:
            body = b'{"id":"fake","choices":[{"message":{"role":"assistant","content":"ok"}}]}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()


class ThreadedHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def start_fake_upstream() -> ThreadedHTTPServer:
    server = ThreadedHTTPServer((UPSTREAM_BIND_HOST, UPSTREAM_PORT), HangingOpenAIHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"[+] Fake upstream started at http://{UPSTREAM_DISPLAY_HOST}:{UPSTREAM_PORT}/v1")
    return server


# Probe NextChat

def probe_nextchat() -> bool:
    print("[*] Probing NextChat route before stress test...")

    payload = {
        "model": "gpt-3.5-turbo",
        "stream": True,
        "messages": [{"role": "user", "content": "probe"}],
    }

    try:
        resp = requests.post(
            NEXTCHAT_URL,
            headers=build_headers(),
            json=payload,
            stream=True,
            timeout=(10, 15),
        )
    except Exception as e:
        print(f"[probe] request failed: {repr(e)}")
        return False

    print(f"[probe] status= {resp.status_code}")

    preview = ""
    try:
        for chunk in resp.iter_content(chunk_size=256):
            if chunk:
                preview = chunk.decode(errors="ignore")[:200]
                break
    except Exception:
        preview = "<streaming or unavailable>"

    print(f"[probe] body= {preview}")

    try:
        resp.close()
    except Exception:
        pass

    if resp.status_code != 200:
        print("[probe] Non-200 response.")
        return False

    time.sleep(2)

    with counter_lock:
        hits = upstream_hits
        streams = upstream_streams_opened

    if hits == 0:
        print("[probe] Upstream was not reached.")
        return False

    if streams == 0:
        print("[probe] Upstream was reached, but no streaming upstream connection was opened.")
        print("[probe] That means the fake upstream did not enter the stream=True branch.")
        return False

    print(f"[probe] Upstream hits: {hits}")
    print(f"[probe] Upstream streams: {streams}")
    return True


# Client worker

def client_worker(idx: int):
    global started_requests, success_200, failed_requests, forbidden_403, other_non_200

    payload = {
        "model": "gpt-3.5-turbo",
        "stream": True,
        "messages": [{"role": "user", "content": f"client {idx}"}],
    }

    session = requests.Session()
    active_sessions.append(session)
    resp = None

    try:
        with counter_lock:
            started_requests += 1

        resp = session.post(
            NEXTCHAT_URL,
            headers=build_headers(),
            json=payload,
            stream=True,
            timeout=(15, CLIENT_TIMEOUT_SEC),
        )

        if resp.status_code == 200:
            with counter_lock:
                success_200 += 1
        elif resp.status_code == 403:
            with counter_lock:
                forbidden_403 += 1
        else:
            with counter_lock:
                other_non_200 += 1
            try:
                print(f"[client {idx}] status={resp.status_code} body={resp.text[:200]}")
            except Exception:
                print(f"[client {idx}] status={resp.status_code}")
            return

        if SIMULATE_CLIENT_DISCONNECT:
            deadline = time.time() + CLIENT_DISCONNECT_AFTER_SEC
            for _ in resp.iter_content(chunk_size=128):
                if stop_event.is_set() or time.time() >= deadline:
                    print(f"[client {idx}] disconnecting intentionally")
                    break
            return

        for _ in resp.iter_content(chunk_size=128):
            if stop_event.is_set():
                break
            time.sleep(1)

    except Exception as e:
        with counter_lock:
            failed_requests += 1
        print(f"[client {idx}] error: {repr(e)}")
    finally:
        try:
            if resp is not None:
                resp.close()
        except Exception:
            pass
        try:
            session.close()
        except Exception:
            pass


# Reporter

def reporter():
    while not stop_event.is_set():
        with counter_lock:
            started = started_requests
            ok200 = success_200
            f403 = forbidden_403
            non200 = other_non_200
            failed = failed_requests
            hits = upstream_hits
            streams = upstream_streams_opened
            broken = upstream_broken_pipes

        docker_mem = docker_mem_stats(DOCKER_CONTAINER)

        pid = find_nextchat_pid()
        if pid is not None:
            stats = process_stats(pid)
            if "error" in stats:
                print(
                    "[report]",
                    f"PID={pid}",
                    stats["error"],
                    f"Started={started}",
                    f"200={ok200}",
                    f"403={f403}",
                    f"OtherNon200={non200}",
                    f"Failed={failed}",
                    f"UpstreamHits={hits}",
                    f"Streams={streams}",
                    f"BrokenPipes={broken}",
                    f"DockerMem={docker_mem}",
                )
            else:
                msg = (
                    f"[report] PID={pid} "
                    f"RSS={stats['rss_mb']:.2f} MB "
                    f"VMS={stats['vms_mb']:.2f} MB "
                    f"Connections={stats['num_connections']} "
                    f"Threads={stats['num_threads']} "
                    f"Started={started} "
                    f"200={ok200} "
                    f"403={f403} "
                    f"OtherNon200={non200} "
                    f"Failed={failed} "
                    f"UpstreamHits={hits} "
                    f"Streams={streams} "
                    f"BrokenPipes={broken}"
                )
                if "conn_error" in stats:
                    msg += f" ConnErr={stats['conn_error']}"
                if docker_mem:
                    msg += f" DockerMem={docker_mem}"
                print(msg)
        else:
            print(
                "[report]",
                f"Started={started}",
                f"200={ok200}",
                f"403={f403}",
                f"OtherNon200={non200}",
                f"Failed={failed}",
                f"UpstreamHits={hits}",
                f"Streams={streams}",
                f"BrokenPipes={broken}",
                f"DockerMem={docker_mem}",
            )

        time.sleep(REPORT_EVERY_SEC)


# Main

def main():
    print("=" * 70)
    print("NextChat fetch proxy issue reproducer")
    print("=" * 70)
    print(f"NextChat target URL: {NEXTCHAT_URL}")
    print(f"Fake upstream:       http://{UPSTREAM_DISPLAY_HOST}:{UPSTREAM_PORT}/v1")
    print(f"Concurrent clients:  {CONCURRENT_CLIENTS}")
    print(f"Simulate disconnect: {SIMULATE_CLIENT_DISCONNECT}")
    if DOCKER_CONTAINER:
        print(f"Docker container:    {DOCKER_CONTAINER}")
    print()

    server = start_fake_upstream()
    threading.Thread(target=reporter, daemon=True).start()

    ok = probe_nextchat()
    if not ok:
        print("\n[!] Probe failed. Not launching full stress test.")
        print("[!] Fix the setup first, then rerun.")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            stop_event.set()
            try:
                server.shutdown()
            except Exception:
                pass
            try:
                server.server_close()
            except Exception:
                pass
        return

    print("\nStarting stress test...")

    threads = []
    try:
        for i in range(CONCURRENT_CLIENTS):
            t = threading.Thread(target=client_worker, args=(i,), daemon=True)
            t.start()
            threads.append(t)
            time.sleep(SPAWN_INTERVAL_SEC)

        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\n[!] Stopping...")
    finally:
        stop_event.set()

        for s in active_sessions:
            try:
                s.close()
            except Exception:
                pass

        for t in threads:
            try:
                t.join(timeout=0.1)
            except Exception:
                pass

        try:
            server.shutdown()
        except Exception:
            pass
        try:
            server.server_close()
        except Exception:
            pass


if __name__ == "__main__":
    main()