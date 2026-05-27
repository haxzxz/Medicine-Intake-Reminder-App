import base64
from datetime import datetime, timezone
import json

import requests
from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import UniqueConstraint

from config import Config


db = SQLAlchemy()


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    firebase_uid = db.Column(db.String(128), unique=True, nullable=False, index=True)
    email = db.Column(db.String(255))
    display_name = db.Column(db.String(255))
    photo_url = db.Column(db.Text)
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = db.Column(
        db.DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class Reminder(db.Model):
    __tablename__ = "reminders"
    __table_args__ = (UniqueConstraint("user_id", "client_id", name="uq_reminder_user_client"),)

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    client_id = db.Column(db.Integer, nullable=False)
    medicine_name = db.Column(db.String(255), nullable=False)
    scheduled_time = db.Column(db.DateTime(timezone=True), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False)
    recurrence = db.Column(db.String(16), nullable=False, default="none")
    fired = db.Column(db.Boolean, nullable=False, default=False)
    deleted_at = db.Column(db.DateTime(timezone=True))

    def to_client_json(self):
        return {
            "id": self.client_id,
            "serverId": self.id,
            "medicineName": self.medicine_name,
            "time": self.scheduled_time.isoformat(),
            "createdAt": self.created_at.isoformat(),
            "recurrence": self.recurrence,
            "fired": self.fired,
        }


class ReminderLog(db.Model):
    __tablename__ = "reminder_logs"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False, index=True)
    reminder_client_id = db.Column(db.Integer, nullable=False)
    medicine_name = db.Column(db.String(255), nullable=False)
    scheduled_time = db.Column(db.DateTime(timezone=True), nullable=False)
    fired_at = db.Column(db.DateTime(timezone=True), nullable=False)
    status = db.Column(db.String(24), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    def to_client_json(self):
        return {
            "id": self.id,
            "reminderId": self.reminder_client_id,
            "medicineName": self.medicine_name,
            "scheduledTime": self.scheduled_time.isoformat(),
            "firedAt": self.fired_at.isoformat(),
            "status": self.status,
        }


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    if not app.config["CORS_ORIGINS"]:
        raise RuntimeError(
            "CORS_ORIGINS must be set to one or more trusted origins."
        )
    CORS(app, origins=app.config["CORS_ORIGINS"])
    db.init_app(app)

    with app.app_context():
        db.create_all()

    @app.get("/")
    def index():
        return jsonify({"ok": True, "service": "zam-api"})

    @app.before_request
    def load_user():
        if request.path in {"/", "/api/health"} or request.method == "OPTIONS":
            return
        user_or_response = _get_or_create_user(app)
        if hasattr(user_or_response, "status_code"):
            return user_or_response
        g.current_user = user_or_response

    @app.get("/api/health")
    def health():
        db_ok = True
        db_error = None
        try:
            db.session.execute(db.text("select 1"))
        except Exception as exc:
            db_ok = False
            db_error = str(exc)

        payload = {
            "ok": db_ok,
            "database": "ok" if db_ok else "error",
            "geminiConfigured": bool(app.config["GEMINI_API_KEY"]),
            "model": app.config["GEMINI_MODEL"],
        }
        if db_error:
            payload["databaseError"] = db_error
        return jsonify(payload), 200 if db_ok else 500

    @app.post("/api/chat")
    def chat():
        data = request.get_json(silent=True) or {}
        user_message = (data.get("userMessage") or "").strip()
        reminders = data.get("reminders") or []
        if not user_message:
            return jsonify({"error": "userMessage is required"}), 400

        response, status = _call_gemini(app, user_message, reminders)
        return jsonify(response), status

    @app.get("/api/reminders")
    def list_reminders():
        rows = (
            Reminder.query.filter_by(user_id=g.current_user.id, deleted_at=None)
            .order_by(Reminder.scheduled_time.asc())
            .all()
        )
        return jsonify({"reminders": [row.to_client_json() for row in rows]})

    @app.post("/api/reminders")
    def upsert_reminder():
        data = request.get_json(silent=True) or {}
        row, error = _upsert_reminder_from_payload(g.current_user.id, data)
        if error:
            return jsonify({"error": error}), 400
        db.session.commit()
        return jsonify({"reminder": row.to_client_json()}), 201

    @app.put("/api/reminders/<int:client_id>")
    def update_reminder(client_id):
        data = request.get_json(silent=True) or {}
        data["id"] = client_id
        row, error = _upsert_reminder_from_payload(g.current_user.id, data)
        if error:
            return jsonify({"error": error}), 400
        db.session.commit()
        return jsonify({"reminder": row.to_client_json()})

    @app.delete("/api/reminders/<int:client_id>")
    def delete_reminder(client_id):
        row = Reminder.query.filter_by(
            user_id=g.current_user.id,
            client_id=client_id,
            deleted_at=None,
        ).first()
        if row:
            row.deleted_at = datetime.now(timezone.utc)
            db.session.commit()
        return jsonify({"ok": True})

    @app.delete("/api/reminders")
    def delete_all_reminders():
        now = datetime.now(timezone.utc)
        Reminder.query.filter_by(user_id=g.current_user.id, deleted_at=None).update(
            {"deleted_at": now}
        )
        db.session.commit()
        return jsonify({"ok": True})

    @app.get("/api/reminder-logs")
    def list_logs():
        rows = (
            ReminderLog.query.filter_by(user_id=g.current_user.id)
            .order_by(ReminderLog.fired_at.desc())
            .limit(200)
            .all()
        )
        return jsonify({"logs": [row.to_client_json() for row in rows]})

    @app.post("/api/reminder-logs")
    def append_log():
        data = request.get_json(silent=True) or {}
        row, error = _log_from_payload(g.current_user.id, data)
        if error:
            return jsonify({"error": error}), 400
        db.session.add(row)
        db.session.commit()
        return jsonify({"log": row.to_client_json()}), 201

    return app


def _get_or_create_user(app):
    token = _bearer_token()
    profile = _verify_firebase_token(token) if token else None
    if profile is None and token and not app.config["FIREBASE_AUTH_REQUIRED"]:
        profile = _decode_unverified_firebase_token(token)

    if app.config["FIREBASE_AUTH_REQUIRED"] and not profile:
        return _abort_json("Valid Firebase bearer token is required", 401)

    firebase_uid = (profile or {}).get("uid") or request.headers.get("X-User-Id") or "dev-user"
    email = (profile or {}).get("email") or request.headers.get("X-User-Email")
    display_name = (profile or {}).get("name") or request.headers.get("X-User-Name")
    photo_url = (profile or {}).get("picture")

    user = User.query.filter_by(firebase_uid=firebase_uid).first()
    if user is None:
        user = User(firebase_uid=firebase_uid)
        db.session.add(user)

    user.email = email
    user.display_name = display_name
    user.photo_url = photo_url
    db.session.commit()
    return user


def _bearer_token():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    return auth.removeprefix("Bearer ").strip()


def _verify_firebase_token(token):
    try:
        import firebase_admin
        from firebase_admin import auth, credentials

        if not firebase_admin._apps:
            try:
                firebase_admin.initialize_app()
            except ValueError:
                firebase_admin.initialize_app(credentials.ApplicationDefault())
        return auth.verify_id_token(token)
    except Exception:
        return None


def _decode_unverified_firebase_token(token):
    try:
        payload = token.split(".")[1]
        padding = "=" * (-len(payload) % 4)
        decoded = base64.urlsafe_b64decode(payload + padding)
        data = json.loads(decoded)
        uid = data.get("user_id") or data.get("sub")
        if not uid:
            return None
        return {
            "uid": uid,
            "email": data.get("email"),
            "name": data.get("name"),
            "picture": data.get("picture"),
        }
    except Exception:
        return None


def _abort_json(message, status):
    response = jsonify({"error": message})
    response.status_code = status
    return response


def _call_gemini(app, user_message, reminders):
    api_key = app.config["GEMINI_API_KEY"]
    model = app.config["GEMINI_MODEL"]
    if not api_key:
        return {"message": "Gemini is not configured on the backend.", "error": "missing_api_key"}, 500

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent?key={api_key}"
    )
    body = {
        "system_instruction": {
            "parts": [{"text": _system_prompt(reminders)}],
        },
        "contents": [{"role": "user", "parts": [{"text": user_message}]}],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 500,
            "responseMimeType": "application/json",
        },
    }

    try:
        res = requests.post(url, json=body, timeout=30)
        if res.status_code != 200:
            return {
                "message": _gemini_error_message(res),
                "error": f"gemini_{res.status_code}",
            }, res.status_code

        payload = res.json()
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text.replace("```json", "").replace("```", "").strip()), 200
    except requests.Timeout:
        return {"message": "Gemini timed out. Please try again.", "error": "timeout"}, 504
    except Exception as exc:
        return {"message": "Backend could not reach Gemini.", "error": str(exc)}, 502


def _system_prompt(reminders):
    active = "None"
    if reminders:
        active = "\n".join(
            [
                f"- id {item.get('id')}: {item.get('medicineName')} at {item.get('time')} "
                f"(status {'taken/completed' if item.get('fired') else 'pending'}, "
                f"repeats {item.get('recurrence', 'none')})"
                for item in reminders
            ]
        )

    return f"""You are Zam, a warm, smart, casual AI medicine reminder assistant.

ACTIVE REMINDERS:
{active}

IMPORTANT STATE RULE:
- ACTIVE REMINDERS is the source of truth. If it says None, tell the user they have no active reminders.
- Ignore older conversation messages that imply a reminder is still active when ACTIVE REMINDERS no longer lists it.
- Completed/taken/missed reminders are history, not active reminders.

SCOPE RULE:
- If the user asks about unrelated topics like coding, sports, politics, entertainment, homework, travel, finance, weather, jokes, or general trivia, politely say you only specialize in medicine information, medicine intakes, and medicine reminders.
- Do not answer unrelated questions. Offer to help with medicine reminders or medicine intake questions instead.

Return ONLY valid JSON:
{{
  "message": "brief warm reply",
  "action": null,
  "reminder": null,
  "suggestions": ["chip 1", "chip 2", "chip 3"]
}}

Supported actions:
- set_reminder at a clock time with reminder {{ "name": "Medicine Name", "time": "HH:MM", "recurrence": "none|daily|weekly" }}
- set_reminder after a relative delay with reminder {{ "name": "Medicine Name", "time": "00:00", "delayMinutes": 1, "recurrence": "none" }}
- delete_reminder with reminder {{ "name": "Medicine Name", "time": "00:00", "recurrence": "none" }}
- snooze_reminder with reminder {{ "name": "Medicine Name", "time": "00:00", "recurrence": "none", "snoozeMinutes": 10 }}
- delete_all

Time rules:
- Always output 24-hour HH:MM.
- For "in X minute(s)" or "after X minute(s)", ALWAYS use delayMinutes instead of rounding to HH:MM.
- Bare 1-6 usually means PM. Bare 7-11 prefers AM unless context says PM.
- tonight/evening/pm means PM. morning means 08:00. bedtime/night means 21:00.
- When checking reminders, list only pending/due reminders as active. Do not call taken/completed reminders set.

Recurrence rules:
- every day/daily/each morning/night means daily.
- weekly/every week means weekly.
- otherwise none.

Medicine rules:
- Extract the real medicine name.
- If no name is given, use Medicine.
- For delete/snooze, choose the closest active reminder name.
"""


def _gemini_error_message(res):
    try:
        message = res.json().get("error", {}).get("message", "")
    except Exception:
        message = ""
    if res.status_code == 429:
        return "Gemini quota is currently exhausted for this backend key/model."
    if res.status_code == 403:
        return "Gemini rejected the backend API key. Check key restrictions and API access."
    return message or f"Gemini error {res.status_code}"


def _upsert_reminder_from_payload(user_id, data):
    try:
        client_id = int(data["id"])
        medicine_name = str(data["medicineName"]).strip()
        scheduled_time = _parse_datetime(data["time"])
        created_at = _parse_datetime(data.get("createdAt")) if data.get("createdAt") else datetime.now(timezone.utc)
    except Exception:
        return None, "Invalid reminder payload"

    if not medicine_name:
        return None, "medicineName is required"

    recurrence = data.get("recurrence") or "none"
    if recurrence not in {"none", "daily", "weekly"}:
        recurrence = "none"

    row = Reminder.query.filter_by(user_id=user_id, client_id=client_id).first()
    if row is None:
        row = Reminder(user_id=user_id, client_id=client_id)
        db.session.add(row)

    row.medicine_name = medicine_name
    row.scheduled_time = scheduled_time
    row.created_at = created_at
    row.recurrence = recurrence
    row.fired = bool(data.get("fired", False))
    row.deleted_at = None
    return row, None


def _log_from_payload(user_id, data):
    try:
        status = str(data.get("status") or "fired")
        if status not in {"fired", "missed", "snoozed", "deleted"}:
            status = "fired"
        return ReminderLog(
            user_id=user_id,
            reminder_client_id=int(data["reminderId"]),
            medicine_name=str(data["medicineName"]).strip(),
            scheduled_time=_parse_datetime(data["scheduledTime"]),
            fired_at=_parse_datetime(data["firedAt"]),
            status=status,
        ), None
    except Exception:
        return None, "Invalid reminder log payload"


def _parse_datetime(value):
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
