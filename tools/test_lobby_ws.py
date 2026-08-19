#!/usr/bin/env python3
"""Probe vs-server-go lobby REST + WS the way GameMaker does.

Mirrors vs-online-mod wiring:
  REST  ?token= query (no Authorization header)
  WS    wss://host/api/v1/lobbies/{code}/ws?token=…  with empty Origin
  frames  text = JSON control; binary = [u8 len][senderId][game packet]
  packets as BasePacket writes them (first byte = type id)

Identities are throwaway POST /auth/register accounts (not guest POST /players).
Host vs non-host follow GM order:
  host  POST /lobbies → enter → WS welcome → SendPlayerInfo
  guest POST /lobbies/join → host member_joined (connected=false; skip SendQueue)
        → guest enter → WS welcome
        → host member_joined (connected=true) → vs_lobby_host_sync() → guest SendQueue
        → guest welcome SendPlayerInfo (third fallback if the second notify is missed)

Usage:
  python3 tools/test_lobby_ws.py
  python3 tools/test_lobby_ws.py --base https://test-api.vividstasis.cn
  python3 tools/test_lobby_ws.py --base https://online-api.vividstasis.cn
"""
from __future__ import annotations

import argparse
import asyncio
import json
import secrets
import ssl
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

try:
    import websockets
    from websockets.exceptions import ConnectionClosed
except ImportError:
    sys.stderr.write("need websockets: python3 -m pip install websockets\n")
    sys.exit(2)


# Packet ids from gml_GlobalScript_register_packet_types / lobby.packet.go
PKT_ADD_SONG = 4
PKT_SEND_QUEUE = 6
PKT_START_COUNTDOWN = 10
PKT_START_GAME = 11
PKT_SEND_READY = 12
PKT_REPORT_SCORE = 20
PKT_UPDATE_SCORE = 22
PKT_SHOW_SCORE = 30
PKT_SHADOW_SONG = 40
PKT_SEND_PLAYER_INFO = 60
PKT_SEND_STICKER = 61
PKT_SUGGEST_SONG = 101

WELCOME_KEYS = ("type", "lobbyId", "code", "hostId", "you", "members")
MEMBER_KEYS = ("playerId", "name", "ready", "scoreFlag", "host", "order", "connected")

results: List[Dict[str, Any]] = []


def rec(name: str, ok: bool, detail: str = "", group: str = "") -> bool:
    row = {"name": name, "ok": bool(ok), "detail": str(detail), "group": group}
    results.append(row)
    mark = "PASS" if ok else "FAIL"
    extra = ("  " + detail) if detail else ""
    print(f"[{mark}] {name}{extra}")
    return bool(ok)


def gm_url_encode(s: str) -> str:
    """RFC 3986 unreserved set, matching vs_online_url_encode (uppercase hex)."""
    out = []
    for b in s.encode("utf-8"):
        if (48 <= b <= 57) or (65 <= b <= 90) or (97 <= b <= 122) or b in (45, 46, 95, 126):
            out.append(chr(b))
        else:
            out.append("%%%02X" % b)
    return "".join(out)


class GMClient:
    """HTTP like GameMaker: query token, JSON body, no Bearer header."""

    def __init__(self, base: str, timeout: float = 20.0):
        self.base = base.rstrip("/")
        self.timeout = timeout
        self.token = ""
        self.player_id = ""
        self.name = ""
        self.email = ""

    def url(self, path: str, authed: bool = True) -> str:
        u = self.base + path
        if authed and self.token:
            sep = "&" if "?" in u else "?"
            u += sep + "token=" + gm_url_encode(self.token)
        return u

    def request(
        self,
        method: str,
        path: str,
        body: Optional[str] = None,
        authed: bool = True,
        extra_headers: Optional[Dict[str, str]] = None,
        token_override: Optional[str] = None,
    ) -> Tuple[int, Any, str]:
        prev = self.token
        if token_override is not None:
            self.token = token_override
        try:
            data = None if body is None else body.encode("utf-8")
            headers = {"Accept": "application/json", "User-Agent": "vs-online-mod-gml-probe"}
            if body is not None:
                headers["Content-Type"] = "application/json"
            if extra_headers:
                headers.update(extra_headers)
            req = urllib.request.Request(self.url(path, authed=authed), data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as res:
                    raw = res.read().decode("utf-8", "replace")
                    status = res.status
            except urllib.error.HTTPError as e:
                raw = e.read().decode("utf-8", "replace")
                status = e.code
            parsed: Any = raw
            if raw:
                try:
                    parsed = json.loads(raw)
                except json.JSONDecodeError:
                    parsed = raw
            return status, parsed, raw
        finally:
            if token_override is not None:
                self.token = prev

    def get(self, path: str, authed: bool = True) -> Tuple[int, Any, str]:
        return self.request("GET", path, authed=authed)

    def post(self, path: str, body: str, authed: bool = True) -> Tuple[int, Any, str]:
        return self.request("POST", path, body=body, authed=authed)

    def delete(self, path: str) -> Tuple[int, Any, str]:
        return self.request("DELETE", path)

    def put(self, path: str, body: str) -> Tuple[int, Any, str]:
        return self.request("PUT", path, body=body)


def ws_url(base: str, code: str, token: str) -> str:
    host = base.rstrip("/")
    if host.startswith("https://"):
        host = "wss://" + host[len("https://") :]
    elif host.startswith("http://"):
        host = "ws://" + host[len("http://") :]
    return host + "/api/v1/lobbies/" + code + "/ws?token=" + gm_url_encode(token)


def strip_sender(payload: bytes) -> Tuple[str, bytes]:
    """Same walk as vs_online_on_ws_frame for opcode 2."""
    if not payload:
        return "", b""
    n = payload[0]
    sender = payload[1 : 1 + n].decode("ascii", "replace")
    return sender, payload[1 + n :]


def pkt_ready(ready: int = 1) -> bytes:
    return bytes([PKT_SEND_READY, ready & 0xFF])


def pkt_add_song(song_id: int = 1, diff: int = 2) -> bytes:
    return bytes([PKT_ADD_SONG]) + struct.pack("<H", song_id) + struct.pack("b", diff)


def pkt_countdown(n: int = 3) -> bytes:
    return bytes([PKT_START_COUNTDOWN]) + struct.pack("b", n)


def pkt_start_game() -> bytes:
    return bytes([PKT_START_GAME])


def pkt_player_info(rate: int = 12000, klass: int = 2, has_bwp: bool = True) -> bytes:
    # Official: u16 rate + u8 class; mod appends bool has_bwp.
    return bytes([PKT_SEND_PLAYER_INFO]) + struct.pack("<H", rate) + bytes([klass, 1 if has_bwp else 0])


def pkt_report_score(pts: float = 990000.0, flag: int = 2) -> bytes:
    return bytes([PKT_REPORT_SCORE]) + struct.pack("<f", pts) + bytes([flag])


def pkt_suggest(diff: int = 2, chart_id: str = "testchart") -> bytes:
    # SuggestSongPacket: s8 diff + buffer_string chart_id (GM buffer_string is NUL-terminated)
    return bytes([PKT_SUGGEST_SONG]) + struct.pack("b", diff) + chart_id.encode("utf-8") + b"\x00"


def pkt_update_score(pts: float = 0.0, flag: int = 1) -> bytes:
    return bytes([PKT_UPDATE_SCORE]) + struct.pack("<f", pts) + bytes([flag])


def pkt_shadow_song() -> bytes:
    return bytes([PKT_SHADOW_SONG])


def pkt_show_score() -> bytes:
    return bytes([PKT_SHOW_SCORE])


def pkt_sticker(sticker: int = 3) -> bytes:
    return bytes([PKT_SEND_STICKER, sticker & 0xFF])


def pkt_opaque(t: int = 99) -> bytes:
    return bytes([t, 0xAA, 0xBB])


def pkt_send_queue(items: Optional[List[Tuple[int, int]]] = None, members: int = 2) -> bytes:
    # Official SendQueue: u8 n, (u16 songId, s8 diff)*, u8 members, (u64 id, u8 ready)*, bool prev
    # Custom member.id is a UUID string; GM still writes buffer_u64. Relay is opaque.
    if items is None:
        items = [(1, 2)]
    out = bytes([PKT_SEND_QUEUE, len(items) & 0xFF])
    for song_id, diff in items:
        out += struct.pack("<H", song_id) + struct.pack("b", diff)
    out += bytes([members & 0xFF])
    for i in range(members):
        out += struct.pack("<Q", i) + bytes([1 if i == 0 else 0])
    out += bytes([0])  # no previous song
    out += b"testchart\x00"  # CustomWP extra chart_id
    return out


def register_account(client: GMClient, role: str) -> Tuple[int, Any, str]:
    nonce = secrets.token_hex(4)
    email = f"gmprobe.{role}.{nonce}@probe.invalid"
    password = "Probe-" + secrets.token_hex(8)
    name = "GMProbe" + role.title()
    body = json.dumps({"email": email, "password": password, "name": name})
    st, parsed, raw = client.post("/api/v1/auth/register", body, authed=False)
    if st in (200, 201) and isinstance(parsed, dict) and parsed.get("token"):
        client.token = parsed["token"]
        client.player_id = parsed.get("playerId") or ""
        client.name = parsed.get("name") or name
        client.email = email
    return st, parsed, raw


def register_ok(st: int, parsed: Any) -> bool:
    if st not in (200, 201) or not isinstance(parsed, dict):
        return False
    if parsed.get("requiresVerification"):
        return False
    return bool(parsed.get("token") and parsed.get("playerId"))


async def drain_binaries(sess: WSSession, timeout: float) -> List[Tuple[str, bytes]]:
    got: List[Tuple[str, bytes]] = []
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            got.append(await sess.recv_binary(timeout=max(0.05, deadline - time.monotonic())))
        except (TimeoutError, asyncio.TimeoutError):
            break
    return got


async def drain_all(sess: WSSession, timeout: float) -> Tuple[List[dict], List[Tuple[str, bytes]]]:
    texts: List[dict] = []
    bins: List[Tuple[str, bytes]] = []
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            kind, payload = await sess.recv(timeout=max(0.05, deadline - time.monotonic()))
        except (TimeoutError, asyncio.TimeoutError):
            break
        if kind == "text" and isinstance(payload, dict):
            texts.append(payload)
        elif kind == "binary":
            bins.append(payload)  # type: ignore
    return texts, bins


def gm_fields_ok(obj: dict, keys: Tuple[str, ...]) -> Tuple[bool, str]:
    missing = [k for k in keys if k not in obj]
    if missing:
        return False, "missing " + ",".join(missing)
    return True, "ok"


class WSSession:
    def __init__(self, conn):
        self.conn = conn
        self.text: List[dict] = []
        self.binary: List[Tuple[str, bytes]] = []

    async def recv(self, timeout: float = 8.0) -> Tuple[str, Any]:
        raw = await asyncio.wait_for(self.conn.recv(), timeout=timeout)
        if isinstance(raw, str):
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                msg = {"type": "raw", "raw": raw}
            self.text.append(msg if isinstance(msg, dict) else {"type": "raw", "raw": raw})
            return "text", msg
        sender, inner = strip_sender(raw)
        self.binary.append((sender, inner))
        return "binary", (sender, inner)

    async def recv_text(self, want_type: Optional[str] = None, timeout: float = 8.0) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            kind, payload = await self.recv(timeout=max(0.1, deadline - time.monotonic()))
            if kind == "text" and isinstance(payload, dict):
                if want_type is None or payload.get("type") == want_type:
                    return payload
        raise TimeoutError("no text frame type=" + str(want_type))

    async def recv_binary(self, timeout: float = 8.0) -> Tuple[str, bytes]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            kind, payload = await self.recv(timeout=max(0.1, deadline - time.monotonic()))
            if kind == "binary":
                return payload  # type: ignore
        raise TimeoutError("no binary frame")

    async def send_bin(self, data: bytes) -> None:
        await self.conn.send(data)


async def connect_gm_ws(url: str, origin: Optional[str] = None) -> WSSession:
    # extra_headers with no Origin approximates desktop GML (AllowEmptyOrigin).
    kwargs: Dict[str, Any] = {
        "open_timeout": 15,
        "close_timeout": 5,
        "max_size": 64 * 1024,
        "ssl": ssl.create_default_context() if url.startswith("wss://") else None,
    }
    # websockets 10/11: extra_headers; 12+: additional_headers. Try both.
    headers = []
    if origin is None:
        pass
    else:
        headers.append(("Origin", origin))
    try:
        conn = await websockets.connect(url, extra_headers=headers, **kwargs)
    except TypeError:
        conn = await websockets.connect(url, additional_headers=dict(headers), **kwargs)
    return WSSession(conn)


async def ws_http_status(url: str) -> Tuple[int, str]:
    """Plain HTTP GET of the WS path — GM would never do this; Gate should 400."""
    def _do() -> Tuple[int, str]:
        req = urllib.request.Request(url.replace("wss://", "https://").replace("ws://", "http://"), method="GET")
        try:
            with urllib.request.urlopen(req, timeout=15) as res:
                return res.status, res.read().decode("utf-8", "replace")[:300]
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")[:300]
        except Exception as e:
            return 0, str(e)

    return await asyncio.to_thread(_do)


async def run(base: str) -> int:
    host = GMClient(base)
    guest = GMClient(base)
    other = GMClient(base)

    # --- REST identity: registered accounts (vs_online_is_account path) ---
    st, body, _ = host.get("/healthz", authed=False)
    rec("GET /healthz", st == 200 and isinstance(body, dict) and body.get("ok") is True,
        f"http={st} body={body}", "rest")

    st, body, raw = register_account(host, "host")
    ok = register_ok(st, body)
    rec("POST /auth/register host account", ok,
        f"http={st} id={host.player_id or (body.get('playerId') if isinstance(body, dict) else raw[:80])}", "rest")
    if not ok:
        why = "requiresVerification" if isinstance(body, dict) and body.get("requiresVerification") else raw[:120]
        rec("abort", False, "could not register host: " + why, "rest")
        return 1

    st, body, raw = register_account(guest, "guest")
    ok = register_ok(st, body)
    rec("POST /auth/register guest account", ok,
        f"http={st} id={guest.player_id or (body.get('playerId') if isinstance(body, dict) else raw[:80])}", "rest")
    if not ok:
        why = "requiresVerification" if isinstance(body, dict) and body.get("requiresVerification") else raw[:120]
        rec("abort", False, "could not register guest: " + why, "rest")
        return 1

    st, body, raw = register_account(other, "match")
    ok = register_ok(st, body)
    rec("POST /auth/register matchmake account", ok,
        f"http={st} id={other.player_id or (body.get('playerId') if isinstance(body, dict) else raw[:80])}", "rest")
    if not ok:
        why = "requiresVerification" if isinstance(body, dict) and body.get("requiresVerification") else raw[:120]
        rec("abort", False, "could not register matchmake: " + why, "rest")
        return 1

    st, body, _ = host.get("/api/v1/players/me")
    rec("GET /players/me ?token= (account email)",
        st == 200 and isinstance(body, dict) and body.get("playerId") == host.player_id and bool(body.get("email")),
        f"http={st} id={body.get('playerId') if isinstance(body, dict) else ''} has_email={isinstance(body, dict) and bool(body.get('email'))}",
        "rest")

    # GM uses query token, never Authorization. Confirm Bearer also works, but
    # the wiring under test is query.
    st, body, _ = host.request(
        "GET", "/api/v1/players/me", authed=False,
        extra_headers={"Authorization": "Bearer " + host.token},
        token_override="",
    )
    rec("GET /players/me Authorization Bearer (not GM path)", st == 200, f"http={st}", "rest")

    # --- create lobby: GM posts raw {"public":true} because `public` is a builtin ---
    st, created, raw = host.post("/api/v1/lobbies", '{"public":true}')
    ok = st == 201 and isinstance(created, dict) and created.get("code") and created.get("lobbyId") is not None
    rec("POST /lobbies {public:true} → 201", ok, f"http={st} {created if isinstance(created, dict) else raw[:120]}", "rest")
    if not ok:
        rec("abort", False, "create lobby failed", "rest")
        return 1
    code = created["code"]
    ok_fields, why = gm_fields_ok(created, ("lobbyId", "code", "hostId", "members"))
    rec("create JSON shape for vs_lobby_enter", ok_fields and created.get("hostId") == host.player_id,
        why + f" hostId={created.get('hostId')} members={len(created.get('members') or [])}", "gml")
    if created.get("members"):
        ok_m, why_m = gm_fields_ok(created["members"][0], MEMBER_KEYS)
        rec("create members[] shape for vs_lobby_build_member", ok_m, why_m, "gml")

    st, listed, _ = host.get("/api/v1/lobbies", authed=False)
    n = 0
    if isinstance(listed, dict) and isinstance(listed.get("lobbies"), list):
        n = len(listed["lobbies"])
        codes = [x.get("code") for x in listed["lobbies"] if isinstance(x, dict)]
        rec("GET /lobbies unauthed (GM count path _authed=false)", st == 200 and code in codes,
            f"http={st} n={n} has_us={code in codes}", "rest")
    else:
        rec("GET /lobbies unauthed (GM count path _authed=false)", False, f"http={st} {listed}", "rest")

    # --- WS gate negatives ---
    gate_url = ws_url(base, code, host.token)
    http_ws = gate_url.replace("wss://", "https://").replace("ws://", "http://")
    gst, gbody = await ws_http_status(http_ws)
    rec(
        "WS path without Upgrade rejected (GM always upgrades)",
        gst in (400, 403, 426),
        f"http={gst} {gbody[:120]}",
        "ws-gate",
    )

    try:
        await connect_gm_ws(ws_url(base, code, ""))
        rec("WS empty token → reject", False, "dial succeeded", "ws-gate")
    except Exception as e:
        rec("WS empty token → reject", True, str(e).split("\n")[0][:160], "ws-gate")

    try:
        await connect_gm_ws(ws_url(base, "ZZZZZZ", host.token))
        rec("WS unknown lobby → reject", False, "dial succeeded", "ws-gate")
    except Exception as e:
        rec("WS unknown lobby → reject", True, str(e).split("\n")[0][:160], "ws-gate")

    try:
        await connect_gm_ws(ws_url(base, code, guest.token))
        rec("WS not-a-member → reject", False, "dial succeeded before join", "ws-gate")
    except Exception as e:
        rec("WS not-a-member → reject", True, str(e).split("\n")[0][:160], "ws-gate")

    # --- Host connects (user: Host Lobby) ---
    host_ws = await connect_gm_ws(gate_url)
    rec("host WS connect empty Origin", True, gate_url.split("?")[0], "ws")
    try:
        welcome = await host_ws.recv_text("welcome", timeout=8)
        ok_w, why_w = gm_fields_ok(welcome, WELCOME_KEYS)
        rec("host welcome text frame", ok_w and welcome.get("you") == host.player_id and welcome.get("code") == code,
            f"you={welcome.get('you')} members={len(welcome.get('members') or [])} {why_w}", "ws")
        rec("welcome opcode is JSON text (GM message_type=1)", welcome.get("type") == "welcome", "type=" + str(welcome.get("type")), "gml")
    except Exception as e:
        rec("host welcome text frame", False, str(e), "ws")
        await host_ws.conn.close()
        return 1

    # GM welcome: send_packet(SendPlayerInfoPacket). Nobody else is Connected yet.
    await host_ws.send_bin(pkt_player_info())
    rec("host welcome SendPlayerInfo (GM)", True, "sent type 60", "gml")

    # --- Non-host: POST /join then host member_joined (connected=false), then guest WS ---
    st, joined, raw = guest.post("/api/v1/lobbies/join", json.dumps({"code": code}))
    rec("POST /lobbies/join {code} (non-host)", st == 200 and isinstance(joined, dict) and joined.get("code") == code,
        f"http={st} members={joined.get('memberCount') if isinstance(joined, dict) else raw[:80]}", "rest")

    try:
        mj = await host_ws.recv_text("member_joined", timeout=8)
        mem = mj.get("member") or {}
        mid = mem.get("playerId")
        rec("host ctrl member_joined", mid == guest.player_id, f"member={mid} connected={mem.get('connected')}", "ws")
        rec("member_joined.connected is false at REST join", mem.get("connected") is False,
            f"connected={mem.get('connected')}", "gml")
    except Exception as e:
        rec("host ctrl member_joined", False, str(e), "ws")

    # GM skips host_sync while connected=false (guest WS is not up yet).
    rec("host skips SendQueue on REST member_joined (GM)", True, "connected=false → no types 6/60/22", "gml")

    guest_ws = await connect_gm_ws(ws_url(base, code, guest.token))
    rec("guest WS connect", True, "code=" + code, "ws")
    try:
        gw = await guest_ws.recv_text("welcome", timeout=8)
        rec("guest welcome roster", gw.get("you") == guest.player_id and len(gw.get("members") or []) >= 2,
            f"you={gw.get('you')} n={len(gw.get('members') or [])} host={gw.get('hostId')}", "ws")
        rec("guest welcome has no song queue", "queue" not in gw and "songs" not in gw,
            "welcome keys=" + ",".join(sorted(gw.keys())), "gml")
    except Exception as e:
        rec("guest welcome roster", False, str(e), "ws")
        await guest_ws.conn.close()
        await host_ws.conn.close()
        return 1

    try:
        mj2 = await host_ws.recv_text("member_joined", timeout=8)
        mem2 = mj2.get("member") or {}
        rec(
            "WS-attach member_joined.connected is true",
            mem2.get("playerId") == guest.player_id and mem2.get("connected") is True,
            f"member={mem2.get('playerId')} connected={mem2.get('connected')}",
            "gml",
        )
    except Exception as e:
        rec("WS-attach member_joined.connected is true", False, str(e), "gml")

    late = await drain_binaries(guest_ws, 0.4)
    late_types = [inner[0] for _, inner in late if inner]
    rec(
        "no SendQueue before host_sync (welcome has no queue)",
        PKT_SEND_QUEUE not in late_types,
        f"got_types={late_types}",
        "gml",
    )

    # GM host_sync on connected:true — guest is now Connected so the queue arrives.
    await host_ws.send_bin(pkt_send_queue([(7, 2)]))
    await host_ws.send_bin(pkt_player_info())
    await host_ws.send_bin(pkt_update_score(123.0, 1))
    replay = await drain_binaries(guest_ws, 2.0)
    replay_types = [inner[0] for _, inner in replay if inner]
    rec(
        "host sync on connected member_joined → guest SendQueue",
        PKT_SEND_QUEUE in replay_types and PKT_SEND_PLAYER_INFO in replay_types,
        f"got_types={replay_types}",
        "gml",
    )

    # GM guest welcome still sends SendPlayerInfo (third fallback if attach notify is missed).
    await guest_ws.send_bin(pkt_player_info())
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("guest welcome SendPlayerInfo reaches host",
            sender == guest.player_id and inner[:1] == bytes([PKT_SEND_PLAYER_INFO]),
            f"from={sender} type={inner[0] if inner else '?'}", "gml")
    except Exception as e:
        rec("guest welcome SendPlayerInfo reaches host", False, str(e), "gml")
    await drain_binaries(host_ws, 0.3)
    await drain_binaries(guest_ws, 0.3)

    # Reconnect supersedes the old socket. Others get member_joined connected=true; no member_left.
    old_guest = guest_ws
    guest_ws = await connect_gm_ws(ws_url(base, code, guest.token))
    try:
        await guest_ws.recv_text("welcome", timeout=8)
        rec("reconnect welcome", True, "", "ws")
    except Exception as e:
        rec("reconnect welcome", False, str(e), "ws")
    try:
        await asyncio.wait_for(old_guest.conn.wait_closed(), timeout=5)
        rec("reconnect supersedes old socket", True, "", "ws")
    except Exception as e:
        rec("reconnect supersedes old socket", False, str(e)[:120], "ws")
        try:
            await old_guest.conn.close()
        except Exception:
            pass
    recon_texts, _ = await drain_all(host_ws, 1.5)
    recon_types = [t.get("type") for t in recon_texts]
    recon_joined = next((t for t in recon_texts if t.get("type") == "member_joined"), None)
    recon_mem = (recon_joined or {}).get("member") or {}
    rec(
        "reconnect emits member_joined connected=true, no member_left",
        recon_joined is not None
        and recon_mem.get("playerId") == guest.player_id
        and recon_mem.get("connected") is True
        and "member_left" not in recon_types,
        f"ctrl={recon_types} connected={recon_mem.get('connected')}",
        "ws",
    )
    await guest_ws.send_bin(pkt_player_info())
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("reconnect SendPlayerInfo reaches host",
            sender == guest.player_id and inner[:1] == bytes([PKT_SEND_PLAYER_INFO]),
            f"from={sender}", "gml")
    except Exception as e:
        rec("reconnect SendPlayerInfo reaches host", False, str(e), "gml")
    await drain_binaries(guest_ws, 0.4)
    await drain_binaries(host_ws, 0.3)

    # Matchmake into this public unstarted room: same join notify as POST /join.
    st, mm, raw = other.post("/api/v1/lobbies/matchmake", "{}")
    joined_us = st == 200 and isinstance(mm, dict) and mm.get("code") == code
    rec("POST /lobbies/matchmake into existing public room", joined_us,
        f"http={st} code={mm.get('code') if isinstance(mm, dict) else raw[:80]} created={mm.get('hostId')==other.player_id if isinstance(mm, dict) else '?'}",
        "rest")
    mm_texts, _ = await drain_all(host_ws, 1.2)
    mm_joined = next((t for t in mm_texts if t.get("type") == "member_joined"), None)
    mm_mem = (mm_joined or {}).get("member") or {}
    rec(
        "matchmake into existing room emits member_joined",
        mm_joined is not None and mm_mem.get("playerId") == other.player_id,
        f"ctrl={[t.get('type') for t in mm_texts]} connected={mm_mem.get('connected')}",
        "ws",
    )
    rec(
        "matchmake REST member_joined.connected is false",
        mm_mem.get("connected") is False,
        f"connected={mm_mem.get('connected')}",
        "gml",
    )
    if joined_us:
        try:
            mm_ws = await connect_gm_ws(ws_url(base, code, other.token))
            w = await mm_ws.recv_text("welcome", timeout=8)
            rec("matchmake joiner welcome", w.get("you") == other.player_id and len(w.get("members") or []) >= 3,
                f"n={len(w.get('members') or [])} you={w.get('you')}", "ws")
            try:
                mj_mm = await host_ws.recv_text("member_joined", timeout=8)
                mem_mm = mj_mm.get("member") or {}
                rec(
                    "matchmake WS-attach member_joined.connected is true",
                    mem_mm.get("playerId") == other.player_id and mem_mm.get("connected") is True,
                    f"connected={mem_mm.get('connected')}",
                    "gml",
                )
            except Exception as e:
                rec("matchmake WS-attach member_joined.connected is true", False, str(e), "gml")
            await host_ws.send_bin(pkt_send_queue())
            await host_ws.send_bin(pkt_player_info())
            got_q = await drain_binaries(mm_ws, 2.0)
            rec(
                "host sync on matchmake connected member_joined → joiner SendQueue",
                any(inner[:1] == bytes([PKT_SEND_QUEUE]) for _, inner in got_q),
                f"got_types={[inner[0] for _, inner in got_q if inner]}",
                "gml",
            )
            await mm_ws.send_bin(pkt_player_info())
            try:
                sender, inner = await host_ws.recv_binary(timeout=8)
                rec("matchmake joiner SendPlayerInfo reaches host",
                    sender == other.player_id and inner[:1] == bytes([PKT_SEND_PLAYER_INFO]),
                    f"from={sender}", "gml")
            except Exception as e:
                rec("matchmake joiner SendPlayerInfo reaches host", False, str(e), "gml")
            await drain_binaries(guest_ws, 0.4)
            other.post("/api/v1/lobbies/" + code + "/leave", "{}")
            try:
                left = await host_ws.recv_text("member_left", timeout=8)
                rec("matchmake joiner leave → member_left", left.get("playerId") == other.player_id,
                    json.dumps(left), "ws")
            except Exception as e:
                rec("matchmake joiner leave → member_left", False, str(e), "ws")
            await drain_all(guest_ws, 0.5)
            await mm_ws.conn.close()
        except Exception as e:
            rec("matchmake joiner welcome", False, str(e), "ws")

    # --- Packet relay as GameMaker send_packet / receive_packet ---
    await host_ws.send_bin(pkt_ready(1))
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("relay SendReady (type 12) binary + sender prefix",
            sender == host.player_id and inner[:1] == bytes([PKT_SEND_READY]) and inner[1:2] == b"\x01",
            f"from={sender} inner={inner.hex()}", "ws")
        rec("GM strip prefix then receive_packet type byte", inner[0] == PKT_SEND_READY, f"type={inner[0]}", "gml")
    except Exception as e:
        rec("relay SendReady (type 12) binary + sender prefix", False, str(e), "ws")

    await host_ws.send_bin(pkt_player_info())
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("relay SendPlayerInfo (type 60, +has_bwp byte)",
            sender == host.player_id and inner[0] == PKT_SEND_PLAYER_INFO and len(inner) >= 5,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("relay SendPlayerInfo (type 60, +has_bwp byte)", False, str(e), "ws")

    await guest_ws.send_bin(pkt_add_song())
    try:
        err = await guest_ws.recv_text("error", timeout=8)
        rec("non-host AddSong → owner_only error text",
            err.get("code") == "owner_only",
            json.dumps(err), "ws")
    except Exception as e:
        rec("non-host AddSong → owner_only error text", False, str(e), "ws")

    # Host should NOT receive the dropped AddSong
    try:
        kind, payload = await asyncio.wait_for(host_ws.recv(), timeout=1.5)
        rec("host does not get non-host AddSong", False, f"got {kind} {payload}", "ws")
    except (asyncio.TimeoutError, TimeoutError):
        rec("host does not get non-host AddSong", True, "no frame (dropped)", "ws")

    await guest_ws.send_bin(pkt_show_score())
    try:
        err = await guest_ws.recv_text("error", timeout=8)
        rec("non-host ShowScore → owner_only error text",
            err.get("code") == "owner_only",
            json.dumps(err), "ws")
    except Exception as e:
        rec("non-host ShowScore → owner_only error text", False, str(e), "ws")
    try:
        kind, payload = await asyncio.wait_for(host_ws.recv(), timeout=1.5)
        rec("host does not get non-host ShowScore", False, f"got {kind} {payload}", "ws")
    except (asyncio.TimeoutError, TimeoutError):
        rec("host does not get non-host ShowScore", True, "no frame (dropped)", "ws")

    await host_ws.send_bin(pkt_add_song(7, 2))
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("host AddSong relayed to guest",
            sender == host.player_id and inner[0] == PKT_ADD_SONG,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("host AddSong relayed to guest", False, str(e), "ws")

    await host_ws.send_bin(pkt_shadow_song())
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("host ShadowSong relayed to guest",
            sender == host.player_id and inner[0] == PKT_SHADOW_SONG,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("host ShadowSong relayed to guest", False, str(e), "ws")

    await host_ws.send_bin(pkt_countdown(3))
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("host StartCountdown relayed", inner[0] == PKT_START_COUNTDOWN and inner[1:2] == b"\x03",
            f"inner={inner.hex()}", "ws")
    except Exception as e:
        rec("host StartCountdown relayed", False, str(e), "ws")

    await guest_ws.send_bin(pkt_suggest())
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("SuggestSong (type 101) relayed to host",
            sender == guest.player_id and inner[0] == PKT_SUGGEST_SONG,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("SuggestSong (type 101) relayed to host", False, str(e), "ws")

    await guest_ws.send_bin(pkt_opaque())
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("unlisted packet type 99 relayed unchanged",
            sender == guest.player_id and inner == bytes([99, 0xAA, 0xBB]),
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("unlisted packet type 99 relayed unchanged", False, str(e), "ws")

    await host_ws.send_bin(pkt_start_game())
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("host StartGame relayed", inner[0] == PKT_START_GAME, f"inner={inner.hex()}", "ws")
    except Exception as e:
        rec("host StartGame relayed", False, str(e), "ws")

    await guest_ws.send_bin(pkt_update_score(555.0, 2))
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("guest UpdateScore relayed to host",
            sender == guest.player_id and inner[0] == PKT_UPDATE_SCORE,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("guest UpdateScore relayed to host", False, str(e), "ws")

    await guest_ws.send_bin(pkt_report_score())
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("guest ReportScore relayed to host",
            sender == guest.player_id and inner[0] == PKT_REPORT_SCORE,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("guest ReportScore relayed to host", False, str(e), "ws")

    await host_ws.send_bin(pkt_show_score())
    try:
        sender, inner = await guest_ws.recv_binary(timeout=8)
        rec("host ShowScore relayed to guest",
            sender == host.player_id and inner[0] == PKT_SHOW_SCORE,
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("host ShowScore relayed to guest", False, str(e), "ws")

    await guest_ws.send_bin(pkt_sticker(3))
    try:
        sender, inner = await host_ws.recv_binary(timeout=8)
        rec("guest SendSticker relayed to host",
            sender == guest.player_id and inner[0] == PKT_SEND_STICKER and inner[1:2] == b"\x03",
            f"from={sender} inner={inner.hex()}", "ws")
    except Exception as e:
        rec("guest SendSticker relayed to host", False, str(e), "ws")

    st, members, _ = host.get("/api/v1/lobbies/" + code + "/members")
    ready_ok = False
    if isinstance(members, dict):
        for m in members.get("members") or []:
            if m.get("playerId") == host.player_id and int(m.get("ready") or 0) == 1:
                ready_ok = True
    rec("GET /members reflects SendReady state", st == 200 and ready_ok, f"http={st} {members}", "rest")

    # --- kick (host REST; guest should get kicked text then close) ---
    st, kicked, raw = host.delete("/api/v1/lobbies/" + code + "/members/" + guest.player_id)
    rec("DELETE /lobbies/{code}/members/{id} kick", st == 200, f"http={st} {kicked if isinstance(kicked, dict) else raw[:80]}", "rest")
    try:
        kmsg = await guest_ws.recv_text("kicked", timeout=8)
        rec("kicked-player ctrl kicked", kmsg.get("type") == "kicked", json.dumps(kmsg), "ws")
    except Exception as e:
        rec("kicked-player ctrl kicked", False, str(e), "ws")
    try:
        left = await host_ws.recv_text("member_left", timeout=8)
        rec("host ctrl member_left after kick", left.get("playerId") == guest.player_id,
            json.dumps(left), "ws")
    except Exception as e:
        rec("host ctrl member_left after kick", False, str(e), "ws")

    await guest_ws.conn.close()

    # Rejoin for leave / host-migration path
    st, _, raw = guest.post("/api/v1/lobbies/join", json.dumps({"code": code}))
    rec("rejoin after kick", st == 200, f"http={st}", "rest")
    guest_ws = await connect_gm_ws(ws_url(base, code, guest.token))
    try:
        await guest_ws.recv_text("welcome", timeout=8)
        rec("rejoin welcome", True, "", "ws")
    except Exception as e:
        rec("rejoin welcome", False, str(e), "ws")

    # Drain host's REST + WS-attach member_joined from rejoin
    await drain_all(host_ws, 1.0)

    # After StartGame the room is out of the match pool; matchmake should create.
    st, mm, raw = other.post("/api/v1/lobbies/matchmake", "{}")
    created_new = st == 200 and isinstance(mm, dict) and mm.get("code") and mm.get("code") != code
    rec("POST /lobbies/matchmake after StartGame creates new room", created_new,
        f"http={st} code={mm.get('code') if isinstance(mm, dict) else raw[:80]}", "rest")
    if created_new:
        mm_code = mm["code"]
        try:
            mm_ws = await connect_gm_ws(ws_url(base, mm_code, other.token))
            w = await mm_ws.recv_text("welcome", timeout=8)
            rec("matchmake-created WS welcome", w.get("code") == mm_code, f"code={w.get('code')} you={w.get('you')}", "ws")
            await mm_ws.conn.close()
            other.post("/api/v1/lobbies/" + mm_code + "/leave", "{}")
        except Exception as e:
            rec("matchmake-created WS welcome", False, str(e), "ws")

    # --- host leaves via REST while guest stays → member_left + host_changed ---
    st, leave, _ = host.post("/api/v1/lobbies/" + code + "/leave", "{}")
    rec("POST /lobbies/{code}/leave host", st == 200, f"http={st} {leave}", "rest")
    got_left = False
    got_host = False
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and not (got_left and got_host):
            msg = await guest_ws.recv_text(timeout=max(0.2, deadline - time.monotonic()))
            if msg.get("type") == "member_left" and msg.get("playerId") == host.player_id:
                got_left = True
            if msg.get("type") == "host_changed" and msg.get("hostId") == guest.player_id:
                got_host = True
            if msg.get("type") == "lobby_closed":
                rec("guest got lobby_closed on host leave (disband_on_host_leave)", False, json.dumps(msg), "ws")
                break
    except Exception as e:
        rec("host-leave control frames", False, str(e), "ws")
    rec("guest ctrl member_left (host)", got_left, "", "ws")
    rec("guest ctrl host_changed → guest is host", got_host, "", "ws")

    await host_ws.conn.close()
    st, leave2, _ = guest.post("/api/v1/lobbies/" + code + "/leave", "{}")
    rec("POST /lobbies/{code}/leave guest cleanup", st == 200, f"http={st}", "rest")
    try:
        await guest_ws.conn.close()
    except Exception:
        pass

    # empty join like GM keyboard_string empty
    st, bad, raw = guest.post("/api/v1/lobbies/join", json.dumps({"code": ""}))
    rec("POST /join empty code → 400", st == 400, f"http={st} {bad if isinstance(bad, dict) else raw[:80]}", "rest")

    passed = sum(1 for r in results if r["ok"])
    failed = sum(1 for r in results if not r["ok"])
    print(f"\n{passed} passed, {failed} failed, {len(results)} total")
    return 0 if failed == 0 else 1


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="https://online-api.vividstasis.cn")
    p.add_argument("--json", default="")
    args = p.parse_args()
    rc = asyncio.run(run(args.base))
    payload = {"base": args.base, "results": results, "passed": sum(1 for r in results if r["ok"]), "failed": sum(1 for r in results if not r["ok"])}
    if args.json:
        with open(args.json, "w") as f:
            json.dump(payload, f, indent=2)
    else:
        sys.stderr.write(json.dumps({"passed": payload["passed"], "failed": payload["failed"]}) + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main())
