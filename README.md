# Tark Peer — Random Voice Call App

Random strangers se voice call karo, dost banao, practice karo.

---

## Stack

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter (Android + iOS) |
| Backend | FastAPI (Python, async) |
| Database + Auth | Supabase (PostgreSQL) |
| Voice Calls | Agora RTC |
| Matchmaking Queue | Redis |

---

## Project Structure

```
speakr-app/
├── backend/                  # FastAPI backend
│   ├── main.py
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── .env
│   ├── core/
│   │   ├── config.py         # Pydantic settings
│   │   └── dependencies.py   # JWT auth dependency
│   ├── routers/
│   │   ├── auth.py           # POST /auth/verify
│   │   ├── profile.py        # GET/PUT /profile
│   │   ├── call.py           # POST /call/end
│   │   └── match.py          # WebSocket /ws/match
│   ├── services/
│   │   ├── supabase_client.py
│   │   ├── redis_client.py
│   │   └── agora_service.py
│   └── models/
│       └── schemas.py
│
├── flutter_app/              # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── constants.dart
│   │   │   └── theme.dart
│   │   ├── models/
│   │   │   ├── user_profile.dart
│   │   │   └── match_event.dart
│   │   ├── services/
│   │   │   ├── auth_service.dart
│   │   │   ├── profile_service.dart
│   │   │   ├── match_service.dart
│   │   │   ├── call_service.dart
│   │   │   └── friend_service.dart
│   │   ├── screens/
│   │   │   ├── splash_screen.dart
│   │   │   ├── auth/
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── signup_screen.dart
│   │   │   ├── profile/
│   │   │   │   ├── setup_screen.dart
│   │   │   │   └── profile_screen.dart
│   │   │   ├── home/
│   │   │   │   └── home_screen.dart
│   │   │   ├── matching/
│   │   │   │   └── matching_screen.dart
│   │   │   └── call/
│   │   │       └── call_screen.dart
│   │   └── widgets/
│   │       ├── custom_button.dart
│   │       └── user_avatar.dart
│   └── pubspec.yaml
│
└── docker-compose.yml
```

---

## Supabase Tables

| Table | Description |
|-------|-------------|
| `profiles` | User profile — name, age, gender, bio, avatar |
| `call_history` | Call records — user_a, user_b, duration, ended_by |
| `friendships` | Friend requests — requester, receiver, status (pending/accepted/rejected) |

RLS (Row Level Security) sab tables pe enabled hai.

---

## App Screens

| Screen | Route | Description |
|--------|-------|-------------|
| Splash | `/` | Session check, redirect |
| Login | `/login` | Email + password login |
| Signup | `/signup` | Account banana |
| Setup | `/setup` | Profile complete karo |
| Home | `/home` | 3 tabs: Learn, Practice, Progress |
| Profile | `/profile` | Profile dekho, friends, calls, logout |
| Matching | `/matching` | WebSocket se partner dhundho |
| Call | `/call` | Agora voice call, mic toggle, Add Friend |

---

## Backend Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Server status |
| GET | `/stats` | Total/online/offline users |
| POST | `/auth/verify` | JWT validate |
| GET | `/profile/me` | Apna profile |
| PUT | `/profile/me` | Profile update |
| GET | `/profile/history` | Call history |
| GET | `/profile/{id}` | Kisi ka profile |
| POST | `/call/end` | Call khatam karo |
| WS | `/ws/match` | Matchmaking WebSocket |

### WebSocket Events

**Server → Client:**
```json
{"type": "waiting"}
{"type": "matched", "channel_name": "...", "agora_token": "...", "agora_uid": 123, "partner_id": "...", "partner": {...}}
{"type": "call_ended", "reason": "timer|partner_left|manual"}
{"type": "error", "message": "..."}
```

**Client → Server:**
```json
{"type": "cancel"}
{"type": "end_call"}
{"type": "ping"}
```

---

## Run Kaise Karo

### Prerequisites
- Docker Desktop
- Flutter SDK
- JDK 17
- Android device / emulator

### Step 1 — Backend
```bash
cd speakr-app
docker-compose up --build
```

### Step 2 — Test
```bash
curl http://localhost:8000/health
# {"status":"ok","service":"tark-peer"}
```

### Step 3 — Flutter (Android device)
```bash
cd flutter_app
flutter pub get
flutter run -d <device-id>
```

> Android emulator ke liye backend URL: `http://10.0.2.2:8000`
> Real device ke liye: apna PC ka local IP daalo `.env` mein

---

## Environment Variables

### Backend (`backend/.env`)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
AGORA_APP_ID=
AGORA_APP_CERTIFICATE=
REDIS_URL=redis://localhost:6379
JWT_SECRET=
```

### Flutter (`flutter_app/.env`)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
BACKEND_URL=http://10.0.2.2:8000
WS_URL=ws://10.0.2.2:8000/ws/match
```

---

## Features

- Random voice matching (WebSocket + Redis queue)
- 180 second call timer (auto end)
- Friend requests during/after calls
- Notification bell for pending requests
- Call history (last 10 calls)
- Online users count (real-time)
- Dark purple theme
- Stateless backend (scale horizontally)

---

## Important Notes

- Agora App Certificate sirf backend mein rakho — Flutter mein kabhi mat daalo
- `.env` files `.gitignore` mein hain — commit mat karna
- Redis mein saari user state hai — server pe kuch nahi
- Email confirmation Supabase dashboard se disable karo (Authentication → Providers → Email)
- Backend deploy se pehle `GET /health` check kar lena — `{"status": "ok"}` aana chahiye
