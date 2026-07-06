# Tark Peer — CLAUDE.md

Complete reference document for the Tark Peer codebase. Any developer or AI agent reading this should be able to understand the entire system without reading source files.

---

## Critical Rules

### Build Commands
**NEVER run `flutter build`, `flutter pub get`, or any build command** unless the user explicitly says "build karo" or similar. User manages build timing.

### Git
- Commit and push after every meaningful change
- Always use descriptive commit messages
- Never force push to main

---

## 1. Project Overview

Tark Peer is an **English conversation practice app** with two main pillars:

1. **Random voice calls** — match with a random stranger and practice speaking English over a live Agora RTC voice call.
2. **English learning tools** — guided topic levels (Learn tab), games (vocabulary quiz, word scramble, fill in blanks, pronunciation challenge, dictation), and progress tracking.

Additional social features: friend requests, direct friend-to-friend calls, real-time chat (24-hour ephemeral messages), user presence, and **group voice rooms** (private/public, 2–10 members, slot-based layout, Agora multi-user audio).

**Tech Stack:**
- Flutter (Android only) — mobile app
- FastAPI (Python, async) — backend API + WebSocket
- Supabase — PostgreSQL DB + Auth + Realtime broadcasts
- Agora RTC — voice call audio
- Redis — matchmaking queue + call state (horizontally scalable)
- Render.com — backend deployment
- DiceBear API — preset avatar images

**App name in codebase:** `tark_peer` (pubspec) / `com.tarkpeer.tark_peer` (Android package ID)

**Current version:** `1.0.2+3` (pubspec.yaml)

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter App (Android)                                       │
│  • Supabase client (anon key) — DB reads, Auth, Realtime    │
│  • Backend HTTP calls — auth, call end/rate/direct, stats   │
│  • WebSocket to backend — matchmaking queue presence        │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP / WS
┌───────────────────────────▼─────────────────────────────────┐
│  FastAPI Backend (Render.com)                                │
│  • Authenticates via Supabase service key (verifies JWT)    │
│  • Manages matchmaking queue in Redis                       │
│  • Broadcasts match/call events via Supabase Realtime HTTP  │
│  • Generates Agora RTC tokens (never sent to client in URL) │
│  • Writes call_history, call_ratings to Supabase            │
└──────┬────────────────────┬────────────────────────────────┘
       │                    │
┌──────▼──────┐    ┌────────▼────────┐
│   Redis      │    │   Supabase      │
│  • ZSET queue│    │  • auth.users   │
│  • Room state│    │  • profiles     │
│  • Call info │    │  • call_history │
│  • TTL-based │    │  • friendships  │
│    expiry    │    │  • messages     │
└─────────────┘    │  • call_ratings │
                   │  • user_presence│
                   │  • Realtime     │
                   └─────────────────┘
```

**Backend URL:** `https://tark-peer-backend.onrender.com`
**WebSocket URL:** `wss://tark-peer-backend.onrender.com/ws/match`
(Hardcoded in `flutter_app/lib/core/constants.dart`)

**Horizontal scaling:** The backend is fully stateless. All shared state is in Redis. Any number of backend pods can run concurrently. Match events and call lifecycle events travel via Supabase Realtime (HTTP broadcast), not in-process.

---

## 3. Backend Structure

### `backend/main.py` — FastAPI Entry Point

**Lifespan tasks (started on startup, cancelled on shutdown):**
- `call_expiry_scanner` — runs every **15 seconds**, atomically claims rooms whose `end_time` has passed using a Lua script, broadcasts `call_ended` to `room:{channelName}`, closes `call_history` with `ended_by='timer'`, cleans Redis state.
- `message_cleanup` — runs every **3600 seconds (1 hour)**, calls Supabase RPC `delete_expired_messages` to purge expired chat messages.
- `room_expiry_scanner` — runs every **300 seconds (5 minutes)**, calls `room.expire_old_rooms()` to mark expired group rooms as `'ended'` and broadcast `room_ended`.

**Startup sequence:**
1. `redis_client.init_redis()` — connects to Redis
2. `redis_client.clear_stale_state()` — wipes all transient Redis keys from any previous process
3. Launches scanner + cleaner background tasks

**Endpoints:**
- `GET /health` — returns `{"status": "ok", "service": "tark-peer"}`
- `GET /stats` — returns `{total_users, online, waiting, active_calls, offline}`. `online = waiting + active_rooms * 2`. Reads from Redis ZSET card counts.

**Routers included:** `auth`, `profile`, `call`, `match`, `room`

**CORS:** `allow_origins=["*"]`

---

### `backend/core/config.py` — Settings

Pydantic `BaseSettings` reads from `.env`:

| Variable | Description |
|---|---|
| `supabase_url` | Supabase project URL |
| `supabase_anon_key` | Anon key (public) |
| `supabase_service_key` | Service role key (never sent to client) |
| `agora_app_id` | Agora App ID |
| `agora_app_certificate` | Agora App Certificate (backend only) |
| `redis_url` | Redis connection URL (default: `redis://localhost:6379`) |
| `jwt_secret` | (present but token verification uses Supabase `get_user`) |

---

### `backend/core/dependencies.py` — Auth Helpers

- `get_current_user(token: str = Query(...)) -> dict` — FastAPI dependency, validates token via Supabase `get_user`, returns `{id, email}`. Raises 401 on failure.
- `verify_token(token: str) -> dict | None` — non-raising version, returns `None` on invalid.

Both verify against Supabase's auth service using the service key client.

---

### `backend/models/schemas.py` — Pydantic Models

| Model | Fields |
|---|---|
| `UserProfile` | `id, name, age?, gender?, bio?, avatar_url?, is_premium=False, total_calls=0` |
| `UpdateProfile` | `name?, age?, gender?, bio?` — **backend schema only has 4 fields**; Flutter updates profiles directly via Supabase with 10 fields (see ProfileService below) |
| `PartnerInfo` | `name, age?, gender?, avatar_url?, bio?, occupation?, sector?, country?, state?, mother_tongue?` — full profile sent in match payload |
| `MatchEvent` | `type='matched', channel_name, agora_token, agora_uid, agora_app_id, partner_id, partner: PartnerInfo` |
| `DirectCallBody` | `receiver_id` |
| `CallEndEvent` | `channel_name, reason` |
| `CallRateEvent` | `channel_name, rated_user_id, stars` |

---

### `backend/routers/auth.py` — `/auth` Router

| Endpoint | Method | Description |
|---|---|---|
| `/auth/verify` | POST | Validates `Authorization: Bearer <token>`, returns `{user: {id, email}, profile: <profiles row>}` |

---

### `backend/routers/profile.py` — `/profile` Router

All endpoints use `Authorization: Bearer <token>` header.

| Endpoint | Method | Description |
|---|---|---|
| `/profile/me` | GET | Returns caller's full profile row from `profiles` |
| `/profile/me` | PUT | Updates profile fields (non-null only). Sets `updated_at = now()` |
| `/profile/history` | GET | Returns last 50 `call_history` rows where caller is `user_a` or `user_b`, ordered by `started_at` DESC. **Flutter does NOT use this endpoint** — it fetches call history directly from Supabase via `ProfileService.getCallHistory()` with a `.limit(10)` |
| `/profile/{user_id}` | GET | Returns public profile (`id, name, age, gender, bio, avatar_url, is_premium`) for any user |

---

### `backend/routers/call.py` — `/call` Router

All endpoints use `Authorization: Bearer <token>` header.

| Endpoint | Method | Description |
|---|---|---|
| `/call/end` | POST | Body: `CallEndEvent`. Ends a call: looks up partner from Redis, computes duration from `call_info.started_at`, maps reason to `ended_by` (user_a/user_b/timer/disconnect), closes `call_history` row (only if `ended_at IS NULL`), tears down Redis state, broadcasts `call_ended` to `room:{channelName}` Realtime channel. Safe to call multiple times (idempotent). |
| `/call/direct` | POST | Body: `DirectCallBody(receiver_id)`. Initiates a direct friend-to-friend call. Generates Agora tokens for both parties, fetches caller profile, broadcasts `incoming_call` event to `direct:{receiver_id}` Realtime channel. Returns caller's Agora token + channel info. |
| `/call/rate` | POST | Body: `CallRateEvent`. Records 1–5 star rating in `call_ratings`. UPSERTs on `(room_id, rater_id)` — user can change rating before leaving the screen. Cannot rate yourself. |

**`ended_by` mapping in `/call/end`:**
- `reason="timer"` → `ended_by="timer"`
- `reason="disconnect"` → `ended_by="disconnect"`
- anything else ("manual", "skip", "partner_left") → `ended_by="user_a"` if caller is `user_a` in Redis call_info, else `"user_b"`

---

### `backend/routers/room.py` — `/room` Router

All endpoints use `Authorization: Bearer <token>` header.

| Endpoint | Method | Description |
|---|---|---|
| `/room/create` | POST | Body: `{name, type, max_members}`. Creates room in Supabase, assigns host to slot 1, generates Agora token. Returns `RoomInfo`. One active room per user enforced (409 if already in one). |
| `/room/join` | POST | Body: `{code}`. Finds lowest free slot (1..max_members), inserts member row, returns `RoomInfo`. 409 if full or already in room. |
| `/room/leave` | POST | Body: `{room_id}`. Sets `is_active=false`, records `left_at`. If host and last member, marks room `ended`. Broadcasts `member_left` to `room:{code}` Realtime channel. |
| `/room/public` | GET | Returns list of `active` + `public` rooms with member counts. Excludes full rooms. |
| `/room/{code}` | GET | Returns current room state (members + slots). Used for rejoin. |

**Key design decisions:**
- Agora channel name: `room_{code}` (e.g., `room_TRK4X2`)
- Code generation: `secrets.choice` over A-Z0-9, 6 chars, up to 10 uniqueness retries
- `_fetch_members_with_profiles`: 2-step batch (members → profiles), sorted by `slot_number`
- `expire_old_rooms()`: queries `expires_at < now()`, updates `status='ended'`, broadcasts `room_ended`
- Rate limit: 10 room creations per hour per user (`rl:room_create:{user_id}`)

**Realtime topics used:**
- `room:{code}` — broadcasts `member_left`, `room_ended` events

---

### `backend/routers/match.py` — WebSocket Matchmaker

**Design philosophy:** The WebSocket is purely a "queue presence" mechanism. Closing the WS = leaving the queue. All match event delivery goes via Supabase Realtime. One WS fast-path delivery also exists for same-pod latency (uses `_active_ws` dict).

**WebSocket endpoint:** `GET /ws/match?token=...&gender=...&age_range=...&min_rating=...&max_rating=...`

**Lifecycle:**
1. Authenticates token via `_authenticate()`.
2. Checks if user is already in a call (`get_user_room`). If yes, sends `already_in_call` and closes.
3. Adds user to Redis `waiting_queue` ZSET.
4. Sends `{"type": "waiting"}` to client.
5. Starts `_matcher_loop` background task.
6. Listens for:
   - `{"type": "cancel"}` → breaks loop
   - `{"type": "ping"}` → responds with `{"type": "pong"}`
7. On disconnect/cancel: cancels matcher, removes from queue.

**`_matcher_loop`:**
- Polls `find_partner()` every 1 second.
- If filter set: fetches partner profile, calls `_partner_matches_filter()`. If no match: puts partner back, continues.
- On match found: calls `_create_match()`, broadcasts to both `user:{id}` Realtime channels, sends WS frame to both (if partner is on same pod), returns.

**Filter fields:** `gender` (case-insensitive exact), `age_range` ("18-22", "22-30", "30-40", "40+"), `min_rating`/`max_rating` (only applied to users with `rating_count > 0`).

**`_create_match(user_a, user_b) -> (payload_a, payload_b)`:**
- Generates UUID channel name
- Creates Agora tokens for both (MD5-based deterministic UID)
- Fetches both profiles in parallel
- Sets Redis state: `user_room:{id}`, `partner:{ch}:{id}`, `call_info:{ch}` HASH, registers in `active_rooms` ZSET
- Inserts `call_history` row (best-effort, failure doesn't abort match)
- Returns per-side match payloads with full partner profile

---

### `backend/services/redis_client.py` — Redis Layer

**Constants:**
- `CALL_DURATION = 1800` (30 minutes)
- `ROOM_TTL = 2100` (CALL_DURATION + 300 — safety net for Redis keys)
- `QUEUE_TTL = 60` (waiters who stop heartbeating are dropped after 60s)
- `WAITING_QUEUE_KEY = "waiting_queue"`
- `ACTIVE_ROOMS_KEY = "active_rooms"`

**Redis key schema:**

| Key | Type | Value | TTL |
|---|---|---|---|
| `waiting_queue` | ZSET | `user_id → unix_ts` | none |
| `user_room:{user_id}` | STR | `channel_name` | ROOM_TTL |
| `partner:{ch}:{user_id}` | STR | `partner_user_id` | ROOM_TTL |
| `call_info:{ch}` | HASH | `{user_a, user_b, started_at, end_time}` | ROOM_TTL |
| `active_rooms` | ZSET | `channel_name → end_time (unix)` | none |

**Lua scripts (atomic, EVALSHA):**

`_FIND_PARTNER_LUA`: Drops stale waiters (score < now - QUEUE_TTL), then finds first entry != me, atomically removes both from queue, returns partner_id or nil. This is what prevents two concurrent pods from claiming the same partner.

`_CLAIM_EXPIRED_LUA`: Gets all `active_rooms` entries with score <= now, removes them atomically, returns list of channel names. This prevents double-expiry across scanner instances.

**Functions:** `init_redis`, `close_redis`, `clear_stale_state`, `add_to_queue`, `remove_from_queue`, `is_in_queue`, `find_partner`, `set_user_room`, `get_user_room`, `delete_user_room`, `set_room_partners`, `get_partner`, `delete_room_partners`, `register_active_room`, `deregister_active_room`, `get_call_info`, `claim_expired_rooms`

---

### `backend/services/agora_service.py` — Token Generation

- `get_uid_from_user_id(user_id)` — MD5 of user_id, takes first 8 hex chars, mod 100_000_000. Deterministic — same user always gets same Agora UID.
- `generate_token(channel_name, user_id, app_id, app_certificate) -> (token, uid)` — builds Agora RTC token with 1-hour expiry using `RtcTokenBuilder.buildTokenWithUid`. Role is `ROLE_PUBLISHER`.

---

### `backend/services/supabase_client.py`

Two clients:
- `supabase_anon` — anon key (not currently used in routes, kept for completeness)
- `supabase_admin` — service role key (used everywhere in backend)

---

### `backend/services/supabase_realtime.py` — Broadcast Helper

`broadcast(topic, event, payload) -> bool`

POSTs to `{supabase_url}/realtime/v1/api/broadcast` with service key auth. Timeout: 5 seconds. Returns `True` on 2xx, `False` otherwise (errors are swallowed + logged — must never crash caller).

**Realtime topics used:**
- `user:{user_id}` — sends `matched` event during matchmaking
- `room:{channel_name}` — sends `call_ended` event when call terminates
- `direct:{user_id}` — sends `incoming_call` event for direct friend calls

---

### `backend/Dockerfile`

```
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

### `backend/requirements.txt`

```
fastapi==0.111.0
uvicorn[standard]==0.30.0
websockets==12.0
python-dotenv==1.0.1
supabase==2.4.6
redis[asyncio]==5.0.4
agora-token-builder==1.0.0
pydantic==2.7.1
pydantic-settings==2.2.1
python-jose[cryptography]==3.3.0
httpx==0.27.0
```

---

## 4. Flutter App Structure

**Package name:** `tark_peer` (pubspec), `com.tarkpeer.tark_peer` (Android)
**Min SDK:** 24 | **Compile SDK:** 36 | **NDK:** 25.1.8937393

### Dependencies (pubspec.yaml)

| Package | Purpose |
|---|---|
| `supabase_flutter ^2.5.6` | DB, auth, realtime |
| `agora_rtc_engine ^6.3.2` | Voice calls |
| `go_router ^14.1.4` | Navigation |
| `provider ^6.1.2` | State (imported but not heavily used — no ChangeNotifier providers registered at root) |
| `web_socket_channel ^2.4.0` | WebSocket to backend matchmaker |
| `flutter_foreground_task ^8.14.0` | Keep call audio alive when screen locks |
| `permission_handler ^11.3.1` | Microphone permission |
| `flutter_dotenv ^5.1.0` | Load `.env` at runtime |
| `shared_preferences ^2.2.3` | Local persistence (onboarding, hints, game progress, topic progress) |
| `cached_network_image ^3.3.1` | Avatar image caching |
| `http ^1.2.0` | HTTP calls to backend |
| `package_info_plus ^8.1.0` | Read app version for update check |
| `url_launcher ^6.3.1` | Open APK download URL |
| `flutter_svg ^2.0.10+1` | SVG logo in auth screens |
| `speech_to_text ^7.0.0` | Pronunciation challenge game |
| `flutter_tts ^4.2.0` | Dictation game (text-to-speech) |
| `confetti ^0.7.0` | Match celebration animation |

### lib/ Folder Layout

```
flutter_app/lib/
├── main.dart                      — App entry, Supabase init, GoRouter config
├── core/
│   ├── constants.dart             — kBackendUrl, kWsUrl, kMaxCallDurationSeconds
│   └── theme.dart                 — Complete design system: colors, ThemeData
├── models/
│   ├── match_event.dart           — MatchEvent (channelName, agoraToken, agoraUid, agoraAppId, partnerId, partner), PartnerInfo (name, age?, gender?, avatarUrl?, bio?, occupation?, sector?, country?, state?, motherTongue?)
│   ├── match_filter.dart          — MatchFilter (gender, ageRange, minRating, maxRating)
│   ├── room_models.dart           — RoomMember, RoomInfo, PublicRoom
│   └── user_profile.dart          — UserProfile (full profile model)
├── data/
│   ├── avatars.dart               — kPresetAvatars (DiceBear URLs list)
│   ├── locations.dart             — kCountryStates Map, kSectors list, kLanguages list
│   └── topics.dart                — TopicLevel class + kTopicLevels (5 levels, 15 topics each)
├── services/
│   ├── auth_service.dart          — Supabase sign-up/sign-in/sign-out
│   ├── profile_service.dart       — getMyProfile, getProfileById, updateProfile, getCallHistory, getCallStats
│   ├── match_service.dart         — WS + Realtime matchmaking client
│   ├── call_service.dart          — Agora RTC engine wrapper
│   ├── call_audio_manager.dart    — Foreground service + phone call audio focus
│   ├── friend_service.dart        — getFriends, sendRequest, acceptRequest, rejectRequest, getFriendshipStatus, getPendingRequests, getPendingCount
│   ├── message_service.dart       — fetchMessages, sendMessage, markRead, subscribeToMessages
│   ├── presence_service.dart      — setOnline/setOffline/setInCall, watchPresence
│   ├── direct_call_service.dart   — singleton, subscribe/unsubscribe incoming calls, initiateCall
│   ├── room_service.dart          — createRoom, joinRoom, leaveRoom, getPublicRooms, getRoomMembers
│   ├── rating_service.dart        — POST /call/rate wrapper
│   ├── update_service.dart        — GitHub releases version check + APK download
│   ├── topic_progress_service.dart — SharedPrefs-backed topic practiced tracking
│   ├── game_progress_service.dart  — SharedPrefs-backed game stars, best scores, streak
│   ├── onboarding_service.dart    — hasSeen / markSeen (SharedPrefs flag)
│   └── home_hints_service.dart    — One-time UI hints (tark button, tab dots)
├── screens/
│   ├── splash_screen.dart
│   ├── onboarding/
│   │   └── onboarding_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── profile/
│   │   ├── setup_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── friends_screen.dart
│   │   ├── friend_profile_screen.dart
│   │   └── call_history_screen.dart
│   ├── home/
│   │   ├── home_screen.dart        — 4-tab shell (Learn, Practice, Games, Progress)
│   │   ├── learn_tab.dart
│   │   ├── games_tab.dart
│   │   ├── progress_tab.dart
│   │   └── topic_level_screen.dart
│   ├── matching/
│   │   └── matching_screen.dart
│   ├── call/
│   │   └── call_screen.dart
│   ├── chat/
│   │   ├── chat_list_screen.dart
│   │   └── chat_screen.dart
│   ├── rooms/
│   │   ├── rooms_screen.dart       — Landing page (3 option cards)
│   │   ├── create_room_screen.dart — Name + type + size picker
│   │   ├── join_room_screen.dart   — 6-char code input
│   │   ├── public_rooms_screen.dart — Public room list
│   │   └── room_lobby_screen.dart  — Live room lobby (member grid + audio)
│   └── games/
│       ├── vocabulary_quiz_screen.dart
│       ├── word_scramble_screen.dart
│       ├── fill_blanks_screen.dart
│       ├── pronunciation_challenge_screen.dart
│       └── dictation_screen.dart
└── widgets/
    ├── user_avatar.dart            — CachedNetworkImage or initial letter fallback
    ├── custom_button.dart          — Loading-aware full-width ElevatedButton
    ├── partner_profile_sheet.dart  — Bottom sheet: partner info + Add Friend
    ├── avatar_picker_sheet.dart    — Grid of preset DiceBear avatars
    └── filter_bottom_sheet.dart    — Match filter sheet (gender/age/rating — currently locked as Premium)
```

---

## 5. GoRouter Routes

| Route | Screen | Notes |
|---|---|---|
| `/` | `SplashScreen` | Checks session, routes to onboarding/login/setup/home |
| `/onboarding` | `OnboardingScreen` | 4-slide intro, first launch only |
| `/login` | `LoginScreen` | Email + password |
| `/signup` | `SignupScreen` | Email + password + name |
| `/setup` | `SetupScreen` | Profile completion (name, age, gender, country, state, occupation, sector, mother tongue, avatar) |
| `/home` | `HomeScreen` | 4-tab shell |
| `/profile` | `ProfileScreen` | Own profile + logout |
| `/friends` | `FriendsScreen` | Friend list with search |
| `/friend/:id` | `FriendProfileScreen` | Friend's full profile |
| `/calls` | `CallHistoryScreen` | Last 10 calls |
| `/chat` | `ChatListScreen` | Friend chat list with presence |
| `/chat/:friendId` | `ChatScreen` | 1:1 ephemeral chat + direct call |
| `/matching` | `MatchingScreen` | WS queue UI, 90s timeout. `state.extra` = `MatchFilter?` |
| `/call` | `CallScreen` | Live Agora call. **`state.extra` = `MatchEvent` (required)** |
| `/learn/level` | `TopicLevelScreen` | Topic list for a level. `state.extra` = `TopicLevel` |
| `/games/vocab?level=N` | `VocabularyQuizScreen` | Vocab quiz, level 1–3 |
| `/games/scramble?level=N` | `WordScrambleScreen` | Word scramble, level 1–3 |
| `/games/fill?level=N` | `FillBlanksScreen` | Fill in blanks, level 1–3 |
| `/games/pronun?level=N` | `PronunciationChallengeScreen` | Say the word, mic checks. Level 1–3 |
| `/games/dict?level=N` | `DictationScreen` | Hear TTS, type what you hear. Level 1–3 |
| `/rooms` | `RoomsScreen` | Landing: Create / Join with Code / Public Rooms |
| `/rooms/create` | `CreateRoomScreen` | Room name, type (private/public), size (2/4 free, 6/8/10 premium locked) |
| `/rooms/join` | `JoinRoomScreen` | 6-char uppercase code input |
| `/rooms/public` | `PublicRoomsScreen` | List of active public rooms with join button |
| `/rooms/lobby` | `RoomLobbyScreen` | Live room: member slot grid, speaking glow, mic/speaker controls. **`state.extra` = `RoomInfo` (required)** |

---

## 6. Screens — Detailed Descriptions

### SplashScreen
- 800ms delay, then checks Supabase session.
- No session + never onboarded → `/onboarding`
- No session + onboarded → `/login`
- Has session + profile complete (`age, gender, country, state` all non-null) → `/home`
- Has session + profile incomplete → `/setup`

### OnboardingScreen
- 4 full-screen slides with emoji, title, subtitle.
- "Skip" or "Get Started" → `OnboardingService.markSeen()` → `/login`
- Animated dot indicator, slide-in page transitions.

### LoginScreen / SignupScreen
- Standard form with `AuthService`. On success → `/home` or `/setup`.
- SVG logo from `assets/logos/icon.svg`.

### SetupScreen
- Loads existing profile on open.
- Fields: Name, Age (13–100), Gender, Country (dropdown from `kCountryStates`), State (dropdown if country in map, else free-text), Occupation (free text), Sector (dropdown from `kSectors`), Mother Tongue (dropdown from `kLanguages`), Bio (optional), Avatar (via `AvatarPickerSheet`).
- On save: `ProfileService.updateProfile()` → `/home`.

### HomeScreen
- 4-tab `IndexedStack`: Learn (index 0), Practice (index 1), Games (index 2), Progress (index 3).
- Default tab: **Practice** (index 1).
- AppBar: avatar (→ `/profile`), logo, chat icon (→ `/chat`), notification bell (friend requests badge).
- Fetches stats from `/stats` every 15 seconds, displays live waiting/online/in-call counts.
- Checks for app update 2 seconds after load via `UpdateService`.
- Subscribes to `DirectCallService` — shows incoming call dialog with 30s auto-decline timer.
- Sets user presence to `online` on init, `offline` on dispose.
- **Double-back-press to exit** (PopScope).
- One-time hints: bouncing arrow above "Tark Here" button, pulse dots on Learn/Games tabs.

**Practice Tab (inside HomeScreen):**
- Animated pulsing "Tark Here" circle button (gradient orange-gold).
- Tapping → shows filter sheet → navigates to `/matching` with `MatchFilter?`.
- Shows profile incomplete banner if `age/gender/country/state` missing.
- Displays live stats pill row (waiting/online/in-call).
- Peak hours card (hardcoded: Lunch 12:30–1:30, Break 3:00–4:00, Evening 8:00–9:00 PM).

### MatchingScreen
- Connects `MatchService` (Realtime + WebSocket).
- 90-second countdown timer with 3-arc `_RingPainter` (green → amber → red segments).
- On `matched` event: confetti + scale celebration overlay → navigate to `/call` after 1.4s.
- Shows active filter chips.
- Cancel button → sends cancel, navigates home.
- Warning: "Non-English speakers will be banned".

### CallScreen
- Receives `MatchEvent` as `state.extra`.
- **Joining phase:** requests microphone permission, joins Agora channel, subscribes to `room:{channelName}` Realtime, starts foreground service + audio focus listener, starts elapsed timer.
- **UI:** dark gradient background (`kCallBgTop → kCallBgBottom`), elapsed timer top-center, partner avatar (pulses when partner speaking), partner name/age/gender/location/occupation/bio, friend row, 3 control buttons (mic/speaker/earbuds), End + Next (skip) buttons.
- **Partner speaking detection:** Agora `onAudioVolumeIndication` callback, fires every 200ms, triggers animated glow around partner avatar.
- **Audio routing:** detects headset/earbuds/Bluetooth auto (read-only UI badge).
- **Add Friend button:** shows/hides based on `_friendStatus` from `getFriendshipStatus`.
- **End call flow:** → unsubscribes Realtime → stops foreground service → POST `/call/end` → `leaveCall()` → rating dialog (if call ≥ 5 seconds and has partner id) → `/home`.
- **Skip:** `_endCall(reason: 'skip', navigateTo: '/matching', askRating: false)` — ends call and immediately queues again.
- **Phone call mute:** `CallAudioManager.onMuteChanged` → `CallService.setMicMuted()` (preserves user's preference when phone call ends).
- **Auto-disconnect:** at `kMaxCallDurationSeconds = 1800` seconds, `_endCall(reason: 'timer')`.
- **Rating dialog:** 1–5 stars, skip button, submits to `RatingService` → POST `/call/rate`.

### ProfileScreen
- Shows own profile: avatar, name, rating badge (if `ratingCount > 0`), bio, age/gender, location, occupation/sector, mother tongue.
- Buttons: Edit Profile (→ `/setup`), Friends card (→ `/friends`), Calls card (→ `/calls`), Logout (with confirm dialog).

### FriendProfileScreen
- Route: `/friend/:id`. Shows another user's full profile (read-only), with "Friend" badge.

### FriendsScreen
- Lists friends with searchable name filter.
- Pull-to-refresh. Each item taps to `/friend/:id`.

### CallHistoryScreen
- Last 10 calls. Each row shows partner name, date/time, duration.
- Tapping a call → `PartnerProfileSheet` bottom sheet with Add Friend.

### ChatListScreen
- Lists friends with last message preview, presence dot (green=online, red=in_call, grey=offline).
- Phone icon calls friend via `DirectCallService.initiateCall` if online.
- Taps to `/chat/:friendId`.

### ChatScreen
- 1:1 chat with friend. Messages delete after 24h (shown in banner + per-message expiry label).
- Realtime subscription via `MessageService.subscribeToMessages` — reloads messages on new insert.
- Presence dot + direct call button in AppBar.

### LearnTab
- Renders `kTopicLevels` (5 levels, 15 topics each). Level 1 always unlocked. Level N+1 unlocks when all N topics practiced.
- Progress bar per level. Tapping locked level shows snackbar.
- Tapping unlocked level → `/learn/level`.

### TopicLevelScreen
- List of topics for a level, with practiced/not-practiced state.
- Tapping topic → bottom sheet with topic text, Copy button, "Use in Next Call" button.
- "Use in Next Call" → `markPracticed()` → `/matching` (no filter).

### GamesTab
- Shows 5 game cards: Vocabulary Quiz, Word Scramble, Fill in Blanks, Pronunciation Challenge, Dictation.
- Each has 3 levels (Easy/Medium/Hard). Level 2 locks until Level 1 has ≥1 star. Level 3 locks until Level 2 has ≥1 star.
- Shows streak banner if streak > 0.
- Star rating + best score displayed per level.

### ProgressTab
- Shows call stats from `ProfileService.getCallStats()`: total calls, total time, streak, longest call, this week vs last week comparison bar.
- Shows game stats from `GameProgressService.instance.getStats()`: games played, accuracy %, day streak.
- Pull-to-refresh.

### Game Screens (all under `screens/games/`)

All game screens:
- Accept `level` as query param (1/2/3).
- 10 questions per session.
- Save results via `GameProgressService.instance.saveResult(game, level, score, total)`.
- Star rating: ≥90% = 3 stars, ≥60% = 2 stars, >0% = 1 star.
- Back navigation with score summary.

| Screen | Game | Tech |
|---|---|---|
| `VocabularyQuizScreen` | Pick correct definition from 4 choices | Hardcoded question pools per level |
| `WordScrambleScreen` | Unscramble shuffled letters | `dart:math` shuffle |
| `FillBlanksScreen` | Complete sentences with missing word | Hardcoded sentence pools |
| `PronunciationChallengeScreen` | Say word aloud, STT checks | `speech_to_text` package |
| `DictationScreen` | Hear sentence (TTS), type what you hear | `flutter_tts` package |

---

## 7. Services — Detailed Descriptions

### AuthService
Thin wrapper around `Supabase.instance.client.auth`. Methods: `signUp`, `signIn`, `signOut`. Properties: `currentUser`, `accessToken`, `isLoggedIn`, `authStream`.

### ProfileService
Uses Supabase client (anon key). All methods query Supabase directly — **does not call the backend `/profile/*` endpoints**.

- `updateProfile(name?, age?, gender?, bio?, occupation?, sector?, country?, state?, motherTongue?, avatarUrl?)` — updates `profiles` table directly via Supabase (10 fields), NOT the backend `PUT /profile/me` (which only accepts 4 fields). Sets `updated_at` locally.

- `getCallHistory()` — **fetches last 10 calls directly from Supabase** (`.limit(10)`), not from backend `/profile/history` endpoint. 4-step process to avoid Supabase FK join issues:
  1. Fetch call rows (last 10, user is `user_a` or `user_b`)
  2. Collect unique partner IDs
  3. Batch fetch partner profiles (`inFilter`)
  4. Merge using spread operator (NOT mutation — Supabase returns immutable maps)
  Returns rows with `user_b_profile` or `user_a_profile` keys added.

- `getCallStats()` — fetches **ALL** call rows (no limit) from Supabase directly, computes entirely client-side:
  - Total calls, total seconds, longest call
  - Streak (consecutive days with ≥1 call, checks today or yesterday as start)
  - This week / last week call counts (ISO week, Monday start)

### MatchService
- `MatchState` enum: `idle, waiting, matched, ended`
- `_matchReceived` flag deduplicates Realtime + WS fast-path `matched` events.
- `connect(token, filter?)` — subscribes Realtime first (4s timeout), then opens WS. Passes filter as query params.
- `disconnect()` — closes WS sink, removes Realtime channel.
- WS messages handled: `waiting`, `matched`, `call_ended`, `error`, `already_in_call`.
- Realtime channel: `user:{my_id}`, event: `matched`.

### CallService
Agora RTC engine wrapper. Key behaviors:
- Default audio route: earpiece (not speakerphone) via `setDefaultAudioRouteToSpeakerphone(false)`.
- Volume indication: every 200ms with `reportVad: true`.
- Partner speaking: any speaker with uid≠0 and volume>25.
- `setMicMuted(bool)` — external mute/unmute (phone call interruption) without changing `_isMicEnabled`.

### CallAudioManager
- EventChannel: `tark_peer/audio_focus` (from `MainActivity.kt`).
- `loss` event → `onMuteChanged(true)`; `gain` event → `onMuteChanged(false)`.
- Foreground service: `serviceId=256`, notification channel `tark_peer_call`, type `microphone`, `stopWithTask=false`.

### FriendService
- `sendRequest(receiverId)` — checks for reverse pending first. If found, accepts it (prevents duplicate rows).
- `getFriends()` — manual 2-step (no FK join): fetch accepted friendships, deduplicate by partner ID, batch-fetch profiles.
- `getPendingRequests()` — uses FK alias `requester:profiles!requester_id(id,name,avatar_url)`.

### MessageService
- Messages have `expires_at` column (24h). Queries filter `gt('expires_at', now)`.
- Realtime subscription on `public.messages` INSERT — triggers callback for new messages.
- `markRead(friendId)` — sets `read_at` on messages from that friend where `read_at IS NULL`.

### PresenceService
- `user_presence` table with `{user_id, status, last_seen}`.
- `watchPresence(friendIds)` — returns `Stream<Map<String, String>>` (userId → status).
- Realtime subscription on `user_presence` table changes triggers re-fetch.
- `setOnline()` / `setOffline()` / `setInCall()` — upsert on `user_presence`.

### DirectCallService
- Singleton (`DirectCallService.instance`).
- Subscribes to Realtime `direct:{userId}` channel, event `incoming_call`.
- `initiateCall(receiverId)` → POST `/call/direct` → returns Agora params for caller.
- `subscribe()` / `unsubscribe()` — called from HomeScreen lifecycle.

### RoomService
HTTP calls to backend room endpoints. All methods use `AuthService().accessToken` bearer token.

- `createRoom({name, type, maxMembers})` → POST `/room/create` → returns `RoomInfo`
- `joinRoom(code)` → POST `/room/join` → returns `RoomInfo`
- `leaveRoom(roomId)` → POST `/room/leave` (fire-and-forget on cleanup)
- `getPublicRooms()` → GET `/room/public` → returns `List<PublicRoom>` (returns `[]` on error, never throws)
- `getRoomMembers(roomId)` → Supabase direct 2-step batch fetch (same immutable-map-spread pattern as `getCallHistory`): fetch `room_members WHERE is_active=true`, then batch-fetch `profiles`, merge → returns `List<RoomMember>` sorted by `slot_number`

### RatingService
- POST `/call/rate` with `{channel_name, rated_user_id, stars}`.

### UpdateService
- Polls `https://api.github.com/repos/Vijayvsnv/tark-peer/releases/latest` on home screen load (2s delay).
- Compares semver: `current < latest` → returns `{version, url}`.
- `openDownloadUrl(url)` → `launchUrl` with `externalApplication` mode.

### TopicProgressService
- Singleton. `SharedPreferences` key: `practiced_topics` (list of `"levelNum:topicIndex"` strings).
- `ValueNotifier<Set<String>> practiced` — reactive; screens rebuild on change.
- Level unlock: level 0 always unlocked; level N unlocked iff all topics in levels 0..N-1 are practiced.

### GameProgressService
- Singleton. Keys pattern: `{game}_stars_{level}`, `{game}_best_{level}`.
- Global: `streak_count`, `streak_last_date`, `total_games`, `total_correct`.
- Streak: increments if last play date is yesterday; resets to 1 if gap > 1 day; ignored if same day.
- Stars: ≥90% → 3, ≥60% → 2, >0% → 1.

### OnboardingService
- `SharedPreferences` key: `onboarding_seen_v1`.

### HomeHintsService
- Singleton. 3 flags in SharedPrefs: `hint_tark_here_seen_v1`, `hint_learn_tab_seen_v1`, `hint_games_tab_seen_v1`.
- `ValueNotifier<bool>` per hint — reactive.

---

## 8. Widgets

### UserAvatar
`CachedNetworkImage` if `imageUrl` is non-empty, else initial-letter `CircleAvatar` with `kPrimary` background.

### CustomButton
Full-width (default) `ElevatedButton` with loading state (replaces text with small `CircularProgressIndicator`).

### PartnerProfileSheet
Bottom sheet: partner name, bio, location, occupation/sector, friendship status. "Add Friend" → `friendService.sendRequest()`. Status is loaded on init.

### AvatarPickerSheet
Grid of `kPresetAvatars` (DiceBear URLs). Returns selected URL to caller via `Navigator.pop(context, url)`.

### FilterBottomSheet (`filter_bottom_sheet.dart`)
Shows gender/age range/rating filters. **All three sections are currently locked as "Premium" features** — tapping any filter shows a snackbar. The "Start Searching" button always returns a `MatchFilter` with null values (no filtering applied). The sheet UI is rendered but non-functional until premium is implemented.

---

## 9. Data Files

### `data/topics.dart`
`TopicLevel` class with `{level, title, subtitle, emoji, color, topics: List<String>}`.

5 levels:
1. Icebreakers (👋, blue) — 15 Hindi/English mixed icebreaker prompts
2. Small Talk (💬, green) — 15 casual conversation topics
3. Deep Dive (🧠, purple) — deeper discussion topics
4. Fun & Games (🎉, orange) — playful topics
5. Debate Club (⚔️, red) — debate/opinion topics

(Exact topics are Hinglish-style conversation starters)

### `data/locations.dart`
- `kCountryStates: Map<String, List<String>>` — countries with state lists (India, US, UK, Canada, Australia, others)
- `kSectors: List<String>` — industry sectors for profile
- `kLanguages: List<String>` — language options for mother tongue

### `data/avatars.dart`
`kPresetAvatars: List<String>` — DiceBear 9.x avatar URLs (notionists, personas, open-peeps, micah, adventurer, lorelei styles). Pastel backgrounds.

---

## 10. Android Config

### `AndroidManifest.xml` Permissions
- `RECORD_AUDIO` — microphone for calls
- `INTERNET` — network
- `BLUETOOTH` / `BLUETOOTH_CONNECT` — Bluetooth headset
- `MODIFY_AUDIO_SETTINGS` — speaker/earpiece switching
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MICROPHONE` — keep call alive
- `WAKE_LOCK` — screen off during call
- `REQUEST_INSTALL_PACKAGES` — APK self-update

### Services
`com.pravera.flutter_foreground_task.service.ForegroundService` with `foregroundServiceType="microphone"` and `stopWithTask="false"`.

### `MainActivity.kt`
Has `EventChannel("tark_peer/audio_focus")` for audio focus change events. Sends `"loss"` on audio focus loss (phone call), `"gain"` on focus regain.

### `build.gradle`
- applicationId: `com.tarkpeer.tark_peer`
- minSdk: 24, compileSdk: 36
- Java/Kotlin target: 1.8

---

## 11. Theme / Design System

All constants in `lib/core/theme.dart`.

**Brand palette (from logo):**
| Constant | Hex | Usage |
|---|---|---|
| `kPrimary` | `#4171B8` | Steel blue — primary interactive, buttons |
| `kPrimaryDeep` | `#102235` | Dark navy — headings, immersive |
| `kPrimaryLight` | `#E8EEF8` | Light tint for chips |
| `kAccent` | `#F05423` | Orange — main CTA (Tark Here button) |
| `kAccentSoft` | `#FCC211` | Gold — gradient end |
| `kCyan` | `#39C6F4` | Sky — speaker button, call glows |
| `kSuccess` | `#22C55E` | Online indicator, friends |
| `kDanger` | `#EF4444` | End call, errors |
| `kBackground` | `#FFFFFF` | Scaffold background |
| `kSurface` | `#F4F6FB` | Cards |
| `kBorder` | `#E5E7EB` | Dividers |
| `kTextPrimary` | `#0B1422` | Headings |
| `kTextSecondary` | `#6B7280` | Body text |
| `kTextMuted` | `#9CA3AF` | Hints, timestamps |
| `kCallBgTop` | `#0B1422` | Call screen gradient top |
| `kCallBgBottom` | `#15243B` | Call screen gradient bottom |

Font family: `Inter` (declared in ThemeData, must be bundled in assets or use system fallback).

---

## 12. Database — Supabase Tables

All inferred from services, schemas, and backend code.

### `profiles`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | FK → `auth.users`. PK |
| `name` | text | Display name |
| `age` | int | Required for profile completion |
| `gender` | text | `male`/`female`/`other`. Required |
| `bio` | text | Optional |
| `avatar_url` | text | DiceBear URL |
| `occupation` | text | Free text |
| `sector` | text | From `kSectors` dropdown |
| `country` | text | Required for profile completion |
| `state` | text | Required for profile completion |
| `mother_tongue` | text | From `kLanguages` dropdown |
| `avg_rating` | numeric | Computed/updated on new ratings |
| `rating_count` | int | Count of ratings received |
| `is_premium` | bool | Default false |
| `total_calls` | int | |
| `updated_at` | timestamptz | |

**Profile complete check** (`UserProfile.isProfileComplete`): `age != null && gender != null && country != null && state != null`.

**RLS:** All authenticated users can SELECT any profile (required for friend names, call history names). Only own row for UPDATE.

### `call_history`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `user_a` | uuid | FK → profiles |
| `user_b` | uuid | FK → profiles |
| `room_id` | text | Agora channel name (UUID) |
| `started_at` | timestamptz | Set on match creation |
| `ended_at` | timestamptz | Null until call ends |
| `duration_seconds` | int | Computed on end |
| `ended_by` | text | CHECK: `['timer','user_a','user_b','disconnect']` |

### `friendships`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `requester_id` | uuid | FK → profiles |
| `receiver_id` | uuid | FK → profiles |
| `status` | text | `pending` / `accepted` / `rejected` |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

### `call_ratings`
| Column | Type | Notes |
|---|---|---|
| `room_id` | text | Part of unique constraint |
| `rater_id` | uuid | Part of unique constraint |
| `rated_id` | uuid | |
| `stars` | int | 1–5 |

Unique constraint: `(room_id, rater_id)` — one rating per rater per call, upsertable.

### `messages`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `sender_id` | uuid | FK → profiles |
| `receiver_id` | uuid | FK → profiles |
| `content` | text | |
| `read_at` | timestamptz | Null until read |
| `expires_at` | timestamptz | 24h from created_at |
| `created_at` | timestamptz | |

Cleanup: Supabase RPC `delete_expired_messages` called by backend hourly.

### `user_presence`
| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid | PK, FK → profiles |
| `status` | text | `online` / `offline` / `in_call` |
| `last_seen` | timestamptz | |

Upserted by client directly (anon key with RLS to own row only).

### `rooms`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `code` | text | 6-char A-Z0-9, unique |
| `name` | text | Room display name |
| `type` | text | `private` / `public` |
| `max_members` | int | CHECK: 2, 4, 6, 8, 10 |
| `host_id` | uuid | FK → auth.users |
| `status` | text | `active` / `ended` |
| `created_at` | timestamptz | |
| `expires_at` | timestamptz | 2 hours from creation — backend scanner marks ended |

RLS: SELECT open to all authenticated. UPDATE restricted to host. INSERT/DELETE via service key only (backend).

### `room_members`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `room_id` | uuid | FK → rooms |
| `user_id` | uuid | FK → auth.users |
| `slot_number` | int | 1..max_members. Partial unique index enforces no duplicate active slots |
| `agora_uid` | bigint | Deterministic MD5-based UID for Agora channel |
| `is_active` | boolean | false when member leaves |
| `joined_at` | timestamptz | |
| `left_at` | timestamptz | Set on leave |

Partial unique indexes:
- `room_members_active_slot` on `(room_id, slot_number) WHERE is_active = true`
- `room_members_active_user` on `(room_id, user_id) WHERE is_active = true`

In Realtime publication (`supabase_realtime`). Flutter subscribes to `room_members` postgres changes to update the member grid live.

---

## 13. Key Features — Implementation Details

### Matchmaking Flow

1. User taps "Tark Here" → filter sheet → `/matching`
2. `MatchService.connect()`:
   - Subscribes to Supabase Realtime `user:{my_id}` (4s timeout or proceed)
   - Opens WebSocket `wss://.../ws/match?token=...&[filter params]`
3. Backend: adds to `waiting_queue` ZSET, starts `_matcher_loop`
4. `_matcher_loop` polls `find_partner()` (atomic Lua) every 1s
5. Match found → `_create_match()`:
   - Generates tokens, room UUID, fetches both profiles
   - Sets all Redis state atomically (pipeline)
   - Inserts `call_history` row
6. Backend broadcasts `matched` to `user:{a}` and `user:{b}` Realtime channels
7. Also sends WS fast-path frame to partner if on same pod
8. Client receives `matched` (Realtime or WS — whichever first, deduped by `_matchReceived` flag)
9. 1.4s celebration → navigate to `/call` with `MatchEvent`

### Call Flow

1. CallScreen receives `MatchEvent` with Agora creds
2. Requests mic permission
3. `CallService.joinCall()` — initializes Agora engine, sets up event handlers, joins channel
4. Subscribes to `room:{channelName}` Realtime for `call_ended` events
5. Starts `CallAudioManager` (foreground service + audio focus)
6. Starts elapsed timer (auto-ends at 1800s)
7. Partner speaking detection via volume callbacks → pulse animation
8. User ends → confirm dialog → `_endCall()`:
   - Unsubscribes Realtime
   - Stops foreground service
   - POST `/call/end` to backend (which broadcasts `call_ended` to partner)
   - `CallService.leaveCall()`
   - Rating dialog (≥5s calls)
   - Navigate to `/home` (or `/matching` if skip)

### Direct Call Flow

1. From ChatListScreen or ChatScreen, tap phone icon
2. Check presence status (offline → block, in_call → block)
3. `DirectCallService.instance.initiateCall(receiverId)` → POST `/call/direct`
4. Backend generates tokens for both parties, broadcasts `incoming_call` to `direct:{receiverId}`
5. Receiver: HomeScreen `_incomingCallSub` fires, shows `_IncomingCallDialog`
6. 30s auto-decline timer. Accept → push `/call` with `MatchEvent` built from broadcast payload.

### Auth Flow

1. Supabase Auth (email/password)
2. JWTs validated by backend via `supabase_admin.auth.get_user(token)`
3. Token passed as `Authorization: Bearer <token>` header for HTTP, `?token=<token>` for WebSocket
4. Client uses `AuthService().accessToken` = `Supabase.instance.client.auth.currentSession?.accessToken`

### Update Flow

1. HomeScreen `initState` → 2s delay → `UpdateService.checkForUpdate()`
2. Fetches GitHub releases API for `Vijayvsnv/tark-peer`
3. Compares semver (3-part). If newer: shows `_UpdateDialog`
4. "Update Now" → `openDownloadUrl` → `launchUrl(externalApplication)` opens APK in browser download
5. User installs from browser download notification

---

## 14. Configuration — Environment Variables

### Backend (`backend/.env`)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
AGORA_APP_ID=
AGORA_APP_CERTIFICATE=
REDIS_URL=
JWT_SECRET=
```

### Flutter (`flutter_app/.env`)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
```
Loaded by `flutter_dotenv` at startup. Listed in `pubspec.yaml` under `flutter.assets`.

**Backend URL is hardcoded** in `lib/core/constants.dart`:
```dart
String get kBackendUrl => 'https://tark-peer-backend.onrender.com';
String get kWsUrl => 'wss://tark-peer-backend.onrender.com/ws/match';
const int kMaxCallDurationSeconds = 1800;
```

---

## 15. Development

### Run Backend Locally

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env  # fill in values
uvicorn main:app --reload --port 8000
```

Or with Docker Compose (starts Redis + backend):
```bash
docker-compose up --build
```
Redis runs on `localhost:6379`. Backend on `localhost:8000`. The docker-compose overrides `REDIS_URL=redis://redis:6379`.

### Run Flutter App

```bash
cd flutter_app
# NEVER run flutter pub get or flutter build unless user explicitly asks
flutter run
flutter run --release
```

Update `lib/core/constants.dart` to point to local backend during dev:
```dart
String get kBackendUrl => 'http://10.0.2.2:8000';  // Android emulator
String get kWsUrl => 'ws://10.0.2.2:8000/ws/match';
```

### Backend Deployment

Deployed on Render.com. Every push to `main` auto-deploys (if configured). Redis: Upstash or Render Redis.

---

## 16. Important Gotchas & Architectural Decisions

### 1. Immutable Maps from Supabase
Supabase returns immutable maps. **Never `map['key'] = value`** on returned data. Always spread:
```dart
return <String, dynamic>{...original, 'new_key': value};
```
The `getCallHistory()` and `getFriends()` methods both use this pattern explicitly.

### 2. Friends — No Duplicate Rows
`sendRequest()` checks for a reverse pending request first. If found, accepts it instead of creating new row. This prevents both-sides-sent → 2 friend entries.

`getFriends()` deduplicates by partner ID using a `Set<String>`.

### 3. Supabase RLS on Profiles — Must Allow Cross-User Reads
`profiles` SELECT policy must allow all authenticated users to read any profile. Without this, friend names, partner names in call history, and call screen info all show as "Unknown".

### 4. Android Background Audio
`CallAudioManager` starts a foreground service (`flutter_foreground_task`, `foregroundServiceType=microphone`) at call start, stops at call end. Required to keep Agora audio alive when screen locks.

`@pragma('vm:entry-point')` annotation is required on `callTaskCallback` top-level function.

### 5. Phone Call Auto-Mute
`MainActivity.kt` listens for `AudioManager` focus changes on `EventChannel("tark_peer/audio_focus")`. Incoming phone call → sends `"loss"` → `_handlePhoneCallMute(true)` → `setMicMuted(true)`. Phone call ends → `"gain"` → restores to user's preference (mic on/off is preserved in `_micEnabled` and only Agora mute state changes).

### 6. Match Event Deduplication
Backend sends `matched` over BOTH Supabase Realtime AND the WebSocket (fast-path for same-pod). Client uses `_matchReceived = true` flag in `MatchService._safeAdd()` to process only the first arrival and discard the second.

### 7. call_expiry_scanner Interval
Changed from 60s to **15s** in `main.py`. Gives ≤15s overrun on call duration in worst case.

### 8. Filter Sheet is Locked (Premium)
All 3 filter options (gender, age range, rating range) are rendered but wrapped in `_LockedSection` that intercepts taps and shows "Premium feature — coming soon!" snackbar. The sheet always returns a `MatchFilter` with all null values. The filter infrastructure in backend and `MatchService` is fully implemented and ready.

### 9. WebSocket as Queue Presence Only
The WS to `/ws/match` has exactly one job: keep the user in the Redis queue while it's open. **No call lifecycle events travel over WS.** The server closes the WS immediately after sending the `matched` frame. All subsequent signalling (call_ended, etc.) goes via Supabase Realtime.

### 10. Agora Token Generation
- `get_uid_from_user_id`: MD5(user_id).hex[:8] % 100_000_000 — deterministic integer UID
- Tokens expire in 1 hour from generation
- App Certificate is backend-only — never sent to client

### 11. ended_by CHECK Constraint
`call_history.ended_by` only accepts `['timer', 'user_a', 'user_b', 'disconnect']`. Backend maps:
- reason `"timer"` → `"timer"`
- reason `"disconnect"` → `"disconnect"`
- anything else (`"manual"`, `"skip"`, `"partner_left"`) → `"user_a"` or `"user_b"` based on who is in Redis `call_info.user_a`

### 12. CALL_DURATION Sync
- Backend: `redis_client.CALL_DURATION = 1800`
- Flutter: `kMaxCallDurationSeconds = 1800`
Both must stay in sync. If changed, update both places.

### 13. Auto-Update Versioning
- `pubspec.yaml` version (e.g., `1.0.2+3`) must be bumped before each release
- GitHub release tag must match version number (e.g., `v1.0.2`)
- `UpdateService` strips the `v` prefix and compares semver

### 14. Redis clear_stale_state on Startup
Backend clears ALL transient Redis keys (`waiting_queue`, `active_rooms`, `user_room:*`, `partner:*`, `call_info:*`) on startup. This means any in-progress calls or queued users from a previous process will be silently dropped on restart. Acceptable trade-off for correctness.

### 15. Room Multi-User Speaking Detection
`CallService.joinCall` now accepts an optional `onVolumesChanged: Function(Map<int, int>)?` callback. In rooms, `uid=0` is the local user. `RoomLobbyScreen` pre-populates `_uidToSlot[0] = widget.room.mySlot` so the local user's slot box also glows. Volume threshold for speaking is `> 25`. The existing `CallScreen` usage is unchanged — `onVolumesChanged` is optional and defaults to null.

### 16. Chat Messages — 24h Expiry
Messages have `expires_at` set server-side (24h from creation). Queries filter `expires_at > now()`. Backend runs `delete_expired_messages` Supabase RPC hourly to actually purge rows.
