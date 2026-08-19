#!/usr/bin/env python3
"""Interactive GameMaker-like lobby client for live packet tests.

Registers a throwaway account, hosts (or joins) a vs-server-go room, and
speaks the same REST + WS + binary packets as vs-online-mod.

Usage:
  python3 tools/play_lobby.py                  # host on test-api
  python3 tools/play_lobby.py --base https://online-api.vividstasis.cn
  python3 tools/play_lobby.py --join ABC123    # join as guest
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import struct
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_lobby_ws as t  # noqa: E402

PKT_NAMES = {
    t.PKT_ADD_SONG: "AddSong",
    t.PKT_SEND_QUEUE: "SendQueue",
    t.PKT_START_COUNTDOWN: "StartCountdown",
    t.PKT_START_GAME: "StartGame",
    t.PKT_SEND_READY: "SendReady",
    t.PKT_REPORT_SCORE: "ReportScore",
    t.PKT_UPDATE_SCORE: "UpdateScore",
    t.PKT_SHOW_SCORE: "ShowScore",
    t.PKT_SHADOW_SONG: "ShadowSong",
    t.PKT_SEND_PLAYER_INFO: "SendPlayerInfo",
    t.PKT_SEND_STICKER: "SendSticker",
    t.PKT_SUGGEST_SONG: "SuggestSong",
}


def gm_str(s: str) -> bytes:
    return (s or "").encode("utf-8") + b"\x00"


def read_cstr(buf: bytes, i: int) -> Tuple[str, int]:
    end = buf.find(b"\x00", i)
    if end < 0:
        return buf[i:].decode("utf-8", "replace"), len(buf)
    return buf[i:end].decode("utf-8", "replace"), end + 1


def pkt_add_song(song_id: int, diff: int, chart_id: str) -> bytes:
    return bytes([t.PKT_ADD_SONG]) + struct.pack("<H", song_id) + struct.pack("b", diff) + gm_str(chart_id)


def pkt_shadow_song(song_id: int, diff: int, chart_id: str) -> bytes:
    return bytes([t.PKT_SHADOW_SONG]) + struct.pack("<H", song_id) + struct.pack("b", diff) + gm_str(chart_id)


def pkt_send_queue(
    items: List[Dict[str, Any]],
    members: List[Dict[str, Any]],
    previous: Optional[Dict[str, Any]] = None,
    winner: str = "",
) -> bytes:
    out = bytes([t.PKT_SEND_QUEUE, len(items) & 0xFF])
    for it in items:
        out += struct.pack("<H", int(it.get("songId") or 0)) + struct.pack("b", int(it.get("difficulty") or 0))
    out += bytes([len(members) & 0xFF])
    for m in members:
        out += gm_str(str(m.get("playerId") or ""))
        out += bytes([int(m.get("ready") or 0) & 0xFF])
        out += struct.pack("<f", float(m.get("score") or 0.0))
        out += bytes([int(m.get("flag") or 1) & 0xFF])
    if previous:
        out += bytes([1])
        out += struct.pack("<H", int(previous.get("songId") or 0))
        out += struct.pack("b", int(previous.get("difficulty") or 0))
        out += gm_str(winner)
    else:
        out += bytes([0])
    for it in items:
        out += gm_str(str(it.get("chart_id") or ""))
    if previous:
        out += gm_str(str(previous.get("chart_id") or ""))
    return out


def pkt_player_info(rate: int = 12000, klass: int = 2, has_bwp: bool = True) -> bytes:
    return bytes([t.PKT_SEND_PLAYER_INFO]) + struct.pack("<H", rate) + bytes([klass, 1 if has_bwp else 0])


def pkt_ready(ready: int) -> bytes:
    return bytes([t.PKT_SEND_READY, ready & 0xFF])


def pkt_countdown(n: int) -> bytes:
    return bytes([t.PKT_START_COUNTDOWN]) + struct.pack("b", n)


def pkt_start_game() -> bytes:
    return bytes([t.PKT_START_GAME])


def pkt_update_score(pts: float, flag: int = 1) -> bytes:
    return bytes([t.PKT_UPDATE_SCORE]) + struct.pack("<f", float(pts)) + bytes([flag & 0xFF])


def pkt_report_score(pts: float, flag: int = 2) -> bytes:
    return bytes([t.PKT_REPORT_SCORE]) + struct.pack("<f", float(pts)) + bytes([flag & 0xFF])


def pkt_show_score() -> bytes:
    return bytes([t.PKT_SHOW_SCORE])


def pkt_sticker(n: int = 3) -> bytes:
    return bytes([t.PKT_SEND_STICKER, n & 0xFF])


def decode_pkt(inner: bytes) -> str:
    if not inner:
        return "empty"
    typ = inner[0]
    name = PKT_NAMES.get(typ, f"type{typ}")
    body = inner[1:]
    try:
        if typ == t.PKT_ADD_SONG and len(body) >= 3:
            song_id, diff = struct.unpack_from("<Hb", body, 0)
            chart, _ = read_cstr(body, 3)
            return f"{name} songId={song_id} diff={diff} chart={chart!r} hex={inner.hex()}"
        if typ == t.PKT_SUGGEST_SONG and body:
            diff = struct.unpack("b", body[:1])[0]
            chart, _ = read_cstr(body, 1)
            return f"{name} diff={diff} chart={chart!r} hex={inner.hex()}"
        if typ == t.PKT_SHADOW_SONG and len(body) >= 3:
            song_id, diff = struct.unpack_from("<Hb", body, 0)
            chart, _ = read_cstr(body, 3)
            return f"{name} songId={song_id} diff={diff} chart={chart!r}"
        if typ == t.PKT_SEND_READY and body:
            return f"{name} ready={body[0]} hex={inner.hex()}"
        if typ == t.PKT_START_COUNTDOWN and body:
            return f"{name} n={struct.unpack('b', body[:1])[0]}"
        if typ in (t.PKT_UPDATE_SCORE, t.PKT_REPORT_SCORE) and len(body) >= 5:
            pts, flag = struct.unpack_from("<fB", body, 0)
            return f"{name} pts={pts:.1f} flag={flag}"
        if typ == t.PKT_SEND_PLAYER_INFO and len(body) >= 3:
            rate, klass = struct.unpack_from("<HB", body, 0)
            bwp = body[3] if len(body) > 3 else 0
            return f"{name} rate={rate} class={klass} has_bwp={bwp} hex={inner.hex()}"
        if typ == t.PKT_SEND_STICKER and body:
            return f"{name} id={body[0]}"
        if typ == t.PKT_SEND_QUEUE:
            return f"{name} bytes={len(inner)} hex={inner.hex()}"
    except Exception as e:
        return f"{name} decode_fail={e} hex={inner.hex()}"
    return f"{name} hex={inner.hex()}"


def ts() -> str:
    return time.strftime("%H:%M:%S")


def log(msg: str) -> None:
    print(f"[{ts()}] {msg}", flush=True)


def register_named(client: t.GMClient, name: str) -> Tuple[int, Any, str]:
    nonce = secrets.token_hex(4)
    email = f"play.{nonce}@probe.invalid"
    password = "Play-" + secrets.token_hex(8)
    body = json.dumps({"email": email, "password": password, "name": name})
    st, parsed, raw = client.post("/api/v1/auth/register", body, authed=False)
    if st in (200, 201) and isinstance(parsed, dict) and parsed.get("token"):
        client.token = parsed["token"]
        client.player_id = parsed.get("playerId") or ""
        client.name = parsed.get("name") or name
        client.email = email
    return st, parsed, raw


class FakeHost:
    def __init__(self, client: t.GMClient, sess: t.WSSession, code: str, host_id: str):
        self.client = client
        self.sess = sess
        self.code = code
        self.me = client.player_id
        self.host_id = host_id
        self.members: Dict[str, Dict[str, Any]] = {}
        self.queue: List[Dict[str, Any]] = []
        self.previous: Optional[Dict[str, Any]] = None
        self.winner = ""
        self.playing = False
        self.reported: Dict[str, bool] = {}
        self._countdown_task: Optional[asyncio.Task] = None
        self._score_task: Optional[asyncio.Task] = None
        self._emote_task: Optional[asyncio.Task] = None
        self._sticker_i = 0
        self.my_score = 0.0
        self.my_flag = 1

    def roster(self) -> List[Dict[str, Any]]:
        rows = list(self.members.values())
        rows.sort(key=lambda m: int(m.get("order") or 0))
        return rows

    def apply_roster(self, members: Any) -> None:
        if not isinstance(members, list):
            return
        for raw in members:
            if not isinstance(raw, dict):
                continue
            pid = str(raw.get("playerId") or "")
            if not pid:
                continue
            cur = self.members.get(pid, {})
            cur.update(
                {
                    "playerId": pid,
                    "name": raw.get("name") or cur.get("name") or "",
                    "ready": int(raw.get("ready") or cur.get("ready") or 0),
                    "flag": int(raw.get("scoreFlag") or cur.get("flag") or 1),
                    "host": bool(raw.get("host") or pid == self.host_id),
                    "order": int(raw.get("order") if raw.get("order") is not None else cur.get("order") or 0),
                    "connected": raw.get("connected") if "connected" in raw else cur.get("connected"),
                    "score": float(cur.get("score") or 0.0),
                }
            )
            self.members[pid] = cur

    def has_guest(self) -> bool:
        return any(pid != self.me and m.get("connected") is True for pid, m in self.members.items())

    def in_lobby_idle(self) -> bool:
        if self.playing:
            return False
        if self._countdown_task and not self._countdown_task.done():
            return False
        return True

    async def send(self, data: bytes, why: str) -> None:
        quiet = data and data[0] == t.PKT_UPDATE_SCORE
        if not quiet:
            log(f"SEND {why} {decode_pkt(data)}")
        await self.sess.send_bin(data)

    async def send_sticker(self, n: Optional[int] = None, why: str = "idle") -> None:
        if n is None:
            n = self._sticker_i % 12
            self._sticker_i += 1
        await self.send(pkt_sticker(n & 0xFF), f"SendSticker {why} id={n}")

    def ensure_emotes(self) -> None:
        if self._emote_task and not self._emote_task.done():
            return
        self._emote_task = asyncio.create_task(self._run_lobby_emotes())

    async def _run_lobby_emotes(self) -> None:
        try:
            while True:
                await asyncio.sleep(20)
                if self.in_lobby_idle() and self.has_guest():
                    await self.send_sticker(why="loop")
        except asyncio.CancelledError:
            return

    async def host_sync(self, why: str) -> None:
        if self.host_id != self.me:
            return
        log(f"host_sync ({why})")
        await self.send(pkt_send_queue(self.queue, self.roster(), self.previous, self.winner), "SendQueue")
        await self.send(pkt_player_info(), "SendPlayerInfo")
        await self.send(pkt_update_score(self.my_score, self.my_flag), "UpdateScore")

    def everyone_ready(self) -> bool:
        if not self.queue:
            return False
        humans = [m for m in self.members.values() if m.get("connected") is not False]
        if len(humans) < 2:
            return False
        return all(int(m.get("ready") or 0) == 1 for m in humans)

    def everyone_reported(self) -> bool:
        humans = [m for m in self.members.values() if m.get("connected") is not False]
        if not humans:
            return False
        return all(self.reported.get(str(m["playerId"]), False) for m in humans)

    async def cancel_countdown(self, why: str) -> None:
        if self._countdown_task and not self._countdown_task.done():
            self._countdown_task.cancel()
            log(f"countdown cancel ({why})")
            await self.send(pkt_countdown(-1), "StartCountdown -1")
        self._countdown_task = None

    async def maybe_start(self) -> None:
        if self.host_id != self.me or self.playing:
            return
        if not self.everyone_ready():
            return
        if self._countdown_task and not self._countdown_task.done():
            return
        log("everyone ready → countdown 3")
        self._countdown_task = asyncio.create_task(self._run_countdown())

    async def _run_countdown(self) -> None:
        try:
            for n in (3, 2, 1):
                await self.send(pkt_countdown(n), f"StartCountdown {n}")
                await asyncio.sleep(1)
            await self.send(pkt_start_game(), "StartGame")
            self.playing = True
            self.reported = {pid: False for pid in self.members}
            if self.queue:
                self.previous = self.queue[0]
                self.queue = self.queue[1:]
            for m in self.members.values():
                m["ready"] = 2
                m["score"] = 0.0
            self.my_score = 0.0
            self.my_flag = 2
            self._score_task = asyncio.create_task(self._run_fake_play())
        except asyncio.CancelledError:
            raise

    async def _run_fake_play(self) -> None:
        try:
            for i in range(240):
                if not self.playing:
                    return
                self.my_score = min(990000.0, 8000.0 * (i + 1))
                await self.send(pkt_update_score(self.my_score, self.my_flag), "UpdateScore")
                await asyncio.sleep(0.5)
        except asyncio.CancelledError:
            return

    async def on_suggest(self, sender: str, inner: bytes) -> None:
        if self.host_id != self.me or len(inner) < 2:
            return
        diff = struct.unpack("b", inner[1:2])[0]
        chart, _ = read_cstr(inner, 2)
        log(f"accept SuggestSong from={sender} → AddSong chart={chart!r} diff={diff}")
        self.queue = [{"songId": 0, "difficulty": diff, "chart_id": chart}]
        for pid, m in self.members.items():
            m["ready"] = 1 if pid == self.me else 0
        await self.send(pkt_add_song(0, diff, chart), "AddSong")
        await self.send(pkt_ready(1), "SendReady host=1 after AddSong")

    async def on_ready(self, sender: str, inner: bytes) -> None:
        ready = inner[1] if len(inner) > 1 else 0
        if sender in self.members:
            self.members[sender]["ready"] = ready
        if ready != 1:
            await self.cancel_countdown(f"unready from={sender}")
            return
        await self.maybe_start()

    async def on_report(self, sender: str, inner: bytes) -> None:
        pts, flag = 0.0, 1
        if len(inner) >= 6:
            pts, flag = struct.unpack_from("<fB", inner, 1)
        if sender in self.members:
            self.members[sender]["score"] = pts
            self.members[sender]["flag"] = flag
        self.reported[sender] = True
        if self.host_id != self.me:
            return
        if not self.reported.get(self.me):
            await self.send(pkt_report_score(self.my_score, self.my_flag), "ReportScore host")
            self.reported[self.me] = True
            if self.me in self.members:
                self.members[self.me]["score"] = self.my_score
                self.members[self.me]["flag"] = self.my_flag
        if self.everyone_reported():
            if self._score_task:
                self._score_task.cancel()
            await asyncio.sleep(0.3)
            await self.send(pkt_show_score(), "ShowScore")
            self.playing = False
            self.winner = ""
            best = None
            best_pts = -1.0
            for m in self.members.values():
                m["ready"] = 0
                if float(m.get("score") or 0) > best_pts:
                    best_pts = float(m.get("score") or 0)
                    best = m
            if best:
                self.winner = str(best.get("name") or "")
            log(f"round done winner={self.winner!r}")

    async def on_player_info(self, sender: str) -> None:
        if sender != self.me and self.host_id == self.me and not self.playing:
            await self.host_sync(f"recv SendPlayerInfo from={sender}")

    async def handle_text(self, msg: dict) -> None:
        kind = str(msg.get("type") or "")
        if kind == "welcome":
            self.host_id = str(msg.get("hostId") or self.host_id)
            self.apply_roster(msg.get("members"))
            log(
                f"welcome you={msg.get('you')} host={self.host_id} "
                f"members={len(self.members)} code={msg.get('code')}"
            )
            await self.send(pkt_player_info(), "SendPlayerInfo welcome")
            return
        if kind == "member_joined":
            mem = msg.get("member") or {}
            mid = str(mem.get("playerId") or "")
            connected = mem.get("connected")
            self.apply_roster([mem] if mem else [])
            log(
                f"member_joined id={mid} name={mem.get('name')!r} "
                f"connected={connected} n={len(self.members)}"
            )
            if connected is True and mid != self.me:
                await self.host_sync("member_joined connected")
                self.ensure_emotes()
                await self.send_sticker(why="welcome")
            else:
                log("skip host_sync (REST join, WS not up yet)")
            return
        if kind == "member_left":
            pid = str(msg.get("playerId") or "")
            self.members.pop(pid, None)
            if msg.get("hostId"):
                self.host_id = str(msg["hostId"])
            log(f"member_left id={pid} host={self.host_id}")
            await self.cancel_countdown("member_left")
            return
        if kind == "error":
            log(f"ctrl error {json.dumps(msg, ensure_ascii=False)}")
            return
        if kind in ("kicked", "lobby_closed", "host_changed"):
            log(f"ctrl {kind} {json.dumps(msg, ensure_ascii=False)}")
            return
        log(f"ctrl {kind} {json.dumps(msg, ensure_ascii=False)[:240]}")

    async def handle_bin(self, sender: str, inner: bytes) -> None:
        quiet = inner[:1] == bytes([t.PKT_UPDATE_SCORE])
        if not quiet:
            log(f"RECV from={sender} {decode_pkt(inner)}")
        if not inner:
            return
        typ = inner[0]
        if typ == t.PKT_SUGGEST_SONG:
            await self.on_suggest(sender, inner)
        elif typ == t.PKT_SEND_READY:
            await self.on_ready(sender, inner)
        elif typ == t.PKT_REPORT_SCORE:
            await self.on_report(sender, inner)
        elif typ == t.PKT_SEND_PLAYER_INFO:
            await self.on_player_info(sender)
        elif typ == t.PKT_SEND_STICKER and sender != self.me and len(inner) > 1:
            reply = (inner[1] + 1) % 12
            await asyncio.sleep(0.4)
            if self.in_lobby_idle():
                await self.send_sticker(reply, why=f"reply to {sender[:8]}")
        elif typ == t.PKT_UPDATE_SCORE and len(inner) >= 6:
            pts, flag = struct.unpack_from("<fB", inner, 1)
            if sender in self.members:
                self.members[sender]["score"] = pts
                self.members[sender]["flag"] = flag


async def loop_ws(game: FakeHost) -> None:
    while True:
        try:
            kind, payload = await game.sess.recv(timeout=60)
        except (TimeoutError, asyncio.TimeoutError):
            continue
        except t.ConnectionClosed as e:
            log(f"WS closed {e}")
            return
        if kind == "text" and isinstance(payload, dict):
            await game.handle_text(payload)
        elif kind == "binary":
            sender, inner = payload  # type: ignore
            await game.handle_bin(sender, inner)


async def run(base: str, join_code: str, public: bool) -> int:
    client = t.GMClient(base)
    st, body, _ = client.get("/healthz", authed=False)
    log(f"GET /healthz http={st} {body}")
    if st != 200:
        log("server not healthy, abort")
        return 1

    st, body, raw = register_named(client, "CursorHost" if not join_code else "CursorGuest")
    if not t.register_ok(st, body):
        log(f"register failed http={st} {raw[:200]}")
        return 1
    log(f"account name={client.name} id={client.player_id} email={client.email}")

    if join_code:
        st, created, raw = client.post("/api/v1/lobbies/join", json.dumps({"code": join_code.upper()}))
        ok = st == 200 and isinstance(created, dict) and created.get("code")
        log(f"JOIN http={st} {created if isinstance(created, dict) else raw[:200]}")
        if not ok:
            return 1
        code = created["code"]
        host_id = str(created.get("hostId") or "")
    else:
        st, created, raw = client.post("/api/v1/lobbies", json.dumps({"public": public}))
        ok = st == 201 and isinstance(created, dict) and created.get("code")
        log(f"CREATE http={st} {created if isinstance(created, dict) else raw[:200]}")
        if not ok:
            return 1
        code = created["code"]
        host_id = str(created.get("hostId") or client.player_id)

    url = t.ws_url(base, code, client.token)
    print("", flush=True)
    print("=" * 60, flush=True)
    print(f"  LOBBY CODE: {code}", flush=True)
    print(f"  Server:     {base}", flush=True)
    print(f"  Role:       {'guest' if join_code else 'HOST'}", flush=True)
    print(f"  Name:       {client.name}", flush=True)
    print("=" * 60, flush=True)
    print("Join: game Custom Server → same API → paste the lobby code.", flush=True)
    print("Host sends stickers in the lobby; pick a song to start (SuggestSong).", flush=True)
    print("", flush=True)

    sess = await t.connect_gm_ws(url)
    game = FakeHost(client, sess, code, host_id)
    if isinstance(created, dict):
        game.apply_roster(created.get("members"))
    try:
        await loop_ws(game)
    finally:
        try:
            client.post("/api/v1/lobbies/" + code + "/leave", "{}")
        except Exception:
            pass
        try:
            await sess.conn.close()
        except Exception:
            pass
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="https://test-api.vividstasis.cn")
    p.add_argument("--join", default="", help="lobby code; omit to host")
    p.add_argument("--private", action="store_true")
    args = p.parse_args()
    return asyncio.run(run(args.base, args.join, public=not args.private))


if __name__ == "__main__":
    sys.exit(main())
