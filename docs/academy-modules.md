# Attendance, family records, weekly schedules, and classroom highlights

## Student records and attendance

Open **Student records** from the live portal menu. A student sees their own
record; parents select only children linked under **Assignments**; teachers see
assigned learners; administrators can select any learner.

The record combines attendance totals, monthly stacked charts, homework counts,
Quran progress/notes, resource counts, and the latest 100 scheduled lessons.
Attendance includes only completed, non-cancelled lessons in the totals. A lesson
without a teacher's mark is **Not recorded**, not automatically absent. The rate
is present / (present + absent), with no percentage when nothing is marked.
Monthly charts use Asia/Karachi by default; the summary API accepts a validated
IANA `timezone_name`. Lesson times display in the viewer's device timezone.

Teachers/admins record attendance in **Attendance → Record attendance**. Parents
and students can view these records but cannot alter them.

## Schedule once

1. Create the teacher and students in **People**.
2. Link each learner to the teacher in **Assignments**. Link each parent to their
   own child separately to enable family records and teacher–parent chat.
3. Open **Weekly schedule → Set weekly schedule** (also linked from Classes).
4. Choose the teacher, learner(s), weekdays, time, IANA timezone, start date,
   duration, and optional end date. Individual lessons require one learner.
5. Save once. Open **Classes** to see automatically generated occurrences.

The saved weekly rule has no expiry unless an end date is selected. The API
materializes the next 45 days whenever an authorized user requests Classes.
Each occurrence has its own enrollment, attendance, and LiveKit room. Repeated
or concurrent refreshes do not duplicate occurrences. Existing gaps after a
period without use are filled from the last generated occurrence. No separate
scheduler service is required. The API/laptop must still run when people use it.

Timezone rules preserve the chosen local time through daylight-saving changes.
A nonexistent spring-forward wall time is skipped; an ambiguous fall-back time
uses its first occurrence. Stop future lessons using **Stop future lessons**;
past lessons and attendance remain. To change a timetable, stop it and create a
replacement. A running lesson is not interrupted when future lessons are stopped.

## Chat and administrator supervision

Teachers can message their linked students, those students' linked parents,
and academy administrators. Student/parent access to contacts remains limited
by assignments. Both **Messages** and in-call **Private chat** use the same
persisted one-to-one conversations. The contact chips identify each person's
role. This is not group broadcast chat.

Administrators have a separate **Chat review** screen for teacher–student and
teacher–parent conversations. It is read-only, shows sender and timestamps,
supports earlier messages, and logs review access in Audit activity. Conversation
lists paginate in batches of 100 and each message page holds up to 100 entries.
Normal participant endpoints still cannot read somebody else's conversation.
The Messages and in-call chat interfaces explicitly disclose administrator
supervision. This chat is access-controlled; it is not end-to-end encrypted.

## Rectangle highlights during screen sharing

1. Join an authorized class as teacher/admin and click **Share screen**.
2. Choose the browser tab, application window, or screen to share.
3. In the academy's shared-screen preview, click **Draw rectangle**.
4. Drag around the portion of the shared text/content, then release. Students
   receive the yellow outlined highlight over their copy of the same video.
5. Add more rectangles, click **Done highlighting** to leave drawing mode, or
   use **Clear highlights** to remove all rectangles from that screen.

The shared screen takes the main classroom area; camera tiles remain below.
Only teachers/admins can publish annotation packets. Students can view but not
draw. Packets are checked against the sender's current screen track, bounded to
50 rectangles and 8 KiB, and use normalized coordinates so different viewport
sizes align. The current snapshot is resent when participants join/reconnect.
Highlights disappear when sharing stops. They are not saved as lesson records.

This draws inside the academy classroom, not over unrelated desktop apps. Keep
the shared source visible in another window/tab while drawing in its classroom
preview. Sharing the entire classroom itself can create a recursive mirror.
Highlights mark screen coordinates, not OCR-selected text: clear/redraw after
scrolling or changing the source document. This does not copy or edit Quran text.

## Updating an existing laptop

Stop the old frontend and backend. Keep Docker Desktop open. Back up academy
data using the documented backup process before applying the database upgrade.
Then pull and run the normal launcher, which applies the additive migration:

```bash
cd ~/Desktop/Al_hassan-quran-acedemy
git stash push -m "Preserve local Flutter lockfile" -- frontend/pubspec.lock
git pull origin main
python3 scripts/local.py backend --web-port 8091
```

In another terminal:

```bash
cd ~/Desktop/Al_hassan-quran-acedemy/frontend
flutter pub get
flutter run -d chrome --web-port=8091 --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

If Python on this Mac needs the certificate bundle previously configured, set
`SSL_CERT_FILE` from `backend/.venv/bin/python -m certifi` in the backend terminal
before starting it. Existing passwords, LiveKit settings, and records remain.
