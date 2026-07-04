# Tark Peer — CLAUDE.md

## Project Overview
Random stranger voice call app. Users match with random people, do voice calls, add friends.

**Stack:**
- Flutter (Android) — mobile app
- FastAPI (Python, async) — backend
- Supabase — PostgreSQL DB + Auth + Realtime
- Agora RTC — voice calls
- Redis — matchmaking queue + call state
- Render.com — backend deployment

---

## Critical Rules

### Build Commands
**NEVER run `flutter build`, `flutter pub get`, or any build command** unless user explicitly says "build karo" or similar. User manages build timing himself.

### Git
- Commit and push after every meaningful change
- Always use descriptive commit messages
- Never force push to main

---

## Project Structure

```
speakr-app/
├── backend/                      # FastAPI
│   ├── main.py                   # App entry, /stats, call_expiry_scanner
│   ├── routers/
│   │   ├── match.py              # WS /ws/match — matchmaking
│   │   └── call.py               # POST /call/end
│   └── services/
│       ├── redis_client.py       # Queue (ZSET), room state, Lua scripts
│       ├── agora_service.py      # Token generation
│       ├── supabase_client.py    # Admin client
│       └── supabase_realtime.py  # HTTP broadcast to Realtime
│
└── flutter_app/lib/
    ├── main.dart                 # GoRouter routes
    ├── core/
    │   ├── constants.dart        # kBackendUrl, kWsUrl, kMaxCallDurationSeconds
    │   └── theme.dart            # kPrimary, kBackground, kSurface, kTextPrimary, kTextSecondary
    ├── models/
    │   ├── match_event.dart      # MatchEvent, PartnerInfo
    │   └── user_profile.dart     # UserProfile
    ├── services/
    │   ├── auth_service.dart     # Supabase auth
    │   ├── profile_service.dart  # getMyProfile, getCallHistory, getCallStats
    │   ├── match_service.dart    # WS connect, Realtime subscribe, find partner
    │   ├── call_service.dart     # Agora RTC join/leave, mic, speaker
    │   ├── call_audio_manager.dart # Foreground service + audio focus
    │   ├── friend_service.dart   # getFriends, sendRequest, acceptRequest
    │   └── update_service.dart   # GitHub releases version check
    ├── screens/
    │   ├── splash_screen.dart
    │   ├── auth/login_screen.dart
    │   ├── auth/signup_screen.dart
    │   ├── profile/setup_screen.dart
    │   ├── profile/profile_screen.dart   # Avatar + Friends/Calls nav buttons
    │   ├── profile/friends_screen.dart   # /friends route
    │   ├── profile/call_history_screen.dart  # /calls route
    │   ├── home/home_screen.dart         # 3 tabs: Learn, Practice, Progress
    │   ├── home/progress_tab.dart        # Stats, streak, longest call, weekly
    │   ├── matching/matching_screen.dart # WS queue + waiting UI
    │   └── call/call_screen.dart         # Agora call UI
    └── widgets/
        ├── user_avatar.dart
        ├── custom_button.dart
        └── partner_profile_sheet.dart    # Reusable bottom sheet (name, bio, Add Friend)
```

---

## Routes (GoRouter)

| Route | Screen |
|-------|--------|
| `/` | SplashScreen |
| `/login` | LoginScreen |
| `/signup` | SignupScreen |
| `/setup` | SetupScreen |
| `/home` | HomeScreen |
| `/profile` | ProfileScreen |
| `/friends` | FriendsScreen |
| `/calls` | CallHistoryScreen |
| `/matching` | MatchingScreen |
| `/call` | CallScreen (requires `MatchEvent` as `state.extra`) |

---

## Supabase Tables

### `profiles`
| Column | Type |
|--------|------|
| id | uuid (FK → auth.users) |
| name | text |
| age | int |
| gender | text |
| bio | text |
| avatar_url | text |
| updated_at | timestamptz |

**RLS:** Anyone authenticated can SELECT. Only own row for UPDATE.

### `call_history`
| Column | Type |
|--------|------|
| id | uuid |
| user_a | uuid |
| user_b | uuid |
| room_id | text |
| started_at | timestamptz |
| ended_at | timestamptz |
| duration_seconds | int |
| ended_by | text — CHECK: `['timer','user_a','user_b','disconnect']` |

### `friendships`
| Column | Type |
|--------|------|
| id | uuid |
| requester_id | uuid |
| receiver_id | uuid |
| status | text — `pending` / `accepted` / `rejected` |
| created_at | timestamptz |
| updated_at | timestamptz |

---

## Matchmaking Flow (Stateless — Option C)

1. Client subscribes to Supabase Realtime `user:{userId}` BEFORE opening WS
2. Client opens WS → `/ws/match?token=...`
3. Backend adds user to Redis ZSET queue (`waiting_queue`)
4. `_matcher_loop` polls Redis every 1s using atomic Lua `find_partner` script
5. Match found → `_create_match` builds Agora tokens, room state in Redis, inserts `call_history`
6. Backend broadcasts `matched` event via Supabase Realtime to both users
7. Same-pod fast-path: also sends via `_active_ws` dict directly
8. `_matchReceived` flag on client deduplicates WS + Realtime
9. Client navigates to `/call` with `MatchEvent`

**Call lifecycle:**
- Max duration: `CALL_DURATION = 6000` (100 min) in `redis_client.py` and `kMaxCallDurationSeconds = 6000` in `constants.dart`
- `call_expiry_scanner` in `main.py` runs every 60s, claims expired rooms atomically
- User ends call → `POST /call/end` → broadcasts `call_ended` to `room:{channelName}` Realtime channel

---

## Key Design Decisions

### Immutable Maps from Supabase
Supabase returns immutable maps. **Never do `map['key'] = value` on returned data.** Always use spread:
```dart
return <String, dynamic>{...original, 'new_key': value};
```
This was the root cause of partner names showing "Unknown" in call history.

### Friends — No Duplicate Entries
`sendRequest()` first checks if a reverse pending request exists. If yes, accepts it instead of creating a new row. This prevents both-sides-sent → duplicate friend entries.

`getFriends()` uses manual 2-step fetch (no FK join) and deduplicates by partner ID. Returns `partner_profile` key with the friend's profile data.

### Supabase RLS — Profiles
`profiles` table has a SELECT policy allowing all authenticated users to read all profiles. Without this, friend names and call history names show as "Unknown"/"Friend".

### Android Background Audio
`CallAudioManager` starts a foreground service (flutter_foreground_task) when call begins, stops when call ends. This keeps audio alive when screen locks.

### Phone Call Auto-Mute
`MainActivity.kt` has an EventChannel `tark_peer/audio_focus`. On audio focus loss (phone call) → sends "loss" → Agora mic muted. On gain → sends "gain" → mic restored.

### Auto-Update System
`UpdateService` checks `https://api.github.com/repos/Vijayvsnv/tark-peer/releases/latest` on app launch (2s delay). If newer version found, shows dialog. "Update Now" opens APK download URL in browser via `url_launcher`. User installs from browser download notification.

**Version format:** `pubspec.yaml` version must be bumped (e.g. `1.0.2+3`) before each release. GitHub tag must match (e.g. `v1.0.2`).

---

## Backend Deployment
- Deployed on **Render.com** at `https://tark-peer-backend.onrender.com`
- Redis: Upstash or Render Redis
- Every push to `main` auto-deploys backend (if Render is configured)

## Environment Variables

**Backend (`backend/.env`):**
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
AGORA_APP_ID=
AGORA_APP_CERTIFICATE=
REDIS_URL=
```

**Flutter (`flutter_app/.env`):**
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
```
Backend URL is hardcoded in `constants.dart` (`kBackendUrl`, `kWsUrl`).

---

## Common Gotchas

1. `ended_by` in `call_history` CHECK constraint — only `['timer','user_a','user_b','disconnect']` allowed
2. Agora App Certificate must NEVER go in Flutter — backend only
3. `flutter_foreground_task` requires `callTaskCallback` to be a top-level function with `@pragma('vm:entry-point')`
4. `MatchEvent` must be passed as `state.extra` to `/call` route — not as query params
5. Redis ZSET for queue — not LIST — so duplicate user entries are impossible
6. `call_expiry_scanner` uses atomic Lua to claim expired rooms — prevents double-processing across pods
