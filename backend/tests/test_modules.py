from datetime import datetime, timedelta, timezone, date
import pytest
from sqlalchemy import select
from app.models import ClassSession, Attendance, now, AuditLog, User
from app.recurrence import occurrence, expand_schedules
from conftest import auth


def rule(**overrides):
    return {"title": "Daily Quran", "teacher_id": 2, "student_ids": [3],
        "start_date": date.today().isoformat(), "local_time": "09:30",
        "timezone": "Asia/Karachi", "weekdays": [0, 1, 2, 3, 4], **overrides}


@pytest.mark.asyncio
async def test_recurring_horizon_rolls_without_duplicates_and_stop_preserves_history(client):
    teacher, learner, other, parent = [await auth(client, i) for i in [2, 3, 5, 4]]
    response = await client.post('/api/schedules', json=rule(), headers=teacher)
    assert response.status_code == 201, response.text
    sid = response.json()['id']
    first = (await client.get('/api/classes', headers=learner)).json()
    assert 25 <= len(first) <= 35
    assert all(c['schedule_id'] == sid for c in first)
    assert len(first) == len((await client.get('/api/classes', headers=learner)).json())
    assert (await client.get('/api/classes', headers=other)).json() == []
    assert (await client.get('/api/schedules', headers=parent)).json()[0]['timezone'] == 'Asia/Karachi'
    async with client.factory() as db:
        user = await db.get(User, 2)
        await expand_schedules(db, user, now() + timedelta(days=50))
        all_rows = list((await db.scalars(select(ClassSession))).all())
        assert len(all_rows) > len(first)
        assert len({c.starts_at for c in all_rows}) == len(all_rows)
        historical = ClassSession(title='Historical', teacher_id=2, starts_at=now()-timedelta(days=1),
            duration=30, schedule_id=sid)
        db.add(historical)
        await db.flush()
        db.add(Attendance(session_id=historical.id, student_id=3, present=True))
        await db.commit()
        old_id = historical.id
    assert (await client.post(f'/api/schedules/{sid}/stop', headers=parent)).status_code == 403
    assert (await client.post(f'/api/schedules/{sid}/stop', headers=teacher)).status_code == 200
    async with client.factory() as db:
        assert (await db.get(ClassSession, old_id)).cancelled is False
        assert await db.scalar(select(Attendance.id).where(Attendance.session_id == old_id))
    assert not any(c['starts_at'] > now().isoformat() for c in (await client.get('/api/classes', headers=teacher)).json())
    future = next(c for c in first if datetime.fromisoformat(c['starts_at']) > now())
    assert (await client.post(f"/api/classes/{future['id']}/room-token", headers=teacher)).status_code == 404


@pytest.mark.asyncio
async def test_schedule_scope_dates_and_timezone_validation(client):
    teacher, other_teacher, student, admin = [await auth(client, i) for i in [2, 6, 3, 1]]
    for data in [rule(timezone='Bad/Zone'), rule(weekdays=[9]), rule(local_time='24:00'),
        rule(end_date=(date.today()-timedelta(days=1)).isoformat()), rule(category='Individual', student_ids=[3,5])]:
        assert (await client.post('/api/schedules', json=data, headers=teacher)).status_code == 422
    assert (await client.post('/api/schedules', json=rule(), headers=student)).status_code == 403
    assert (await client.post('/api/schedules', json=rule(), headers=other_teacher)).status_code == 403
    assert (await client.post('/api/schedules', json=rule(student_ids=[5]), headers=admin)).status_code == 422
    made = await client.post('/api/schedules', json=rule(), headers=teacher)
    assert (await client.post(f"/api/schedules/{made.json()['id']}/stop", headers=other_teacher)).status_code == 404


def test_dst_occurrences_use_wall_clock_and_skip_nonexistent_time():
    assert occurrence(date(2026,3,8), '02:30', 'America/New_York') is None
    assert occurrence(date(2026,3,7), '09:00', 'America/New_York').hour == 14
    assert occurrence(date(2026,3,9), '09:00', 'America/New_York').hour == 13
    assert occurrence(date(2026,11,1), '01:30', 'America/New_York').hour == 5


@pytest.mark.asyncio
async def test_student_summary_parent_scope_and_unrecorded_not_absent(client):
    teacher, parent, other = [await auth(client, i) for i in [2,4,5]]
    for index, present in enumerate([True,False,None]):
        response = await client.post('/api/classes', json={'title':'Review', 'teacher_id':2, 'student_ids':[3],
            'starts_at':(datetime.now(timezone.utc)-timedelta(days=index+1)).isoformat()}, headers=teacher)
        assert response.status_code == 201
        if present is not None:
            assert (await client.put(f"/api/classes/{response.json()['id']}/attendance",
                json={'student_id':3,'present':present}, headers=teacher)).status_code == 200
    result = await client.get('/api/students/3/summary', headers=parent)
    assert result.status_code == 200, result.text
    summary = result.json()
    assert summary['attendance'] == {'total':3,'present':1,'absent':1,'unrecorded':1,'rate':50.0}
    assert sum(m['total'] for m in summary['months']) == 3
    assert {c['status'] for c in summary['lessons']} == {'present','absent','unrecorded'}
    assert (await client.get('/api/students/5/summary', headers=parent)).status_code == 404
    assert (await client.get('/api/students/3/summary', headers=other)).status_code == 404
    assert (await client.get('/api/students/3/summary?timezone_name=Invalid', headers=teacher)).status_code == 422


@pytest.mark.asyncio
async def test_teacher_contacts_and_explicit_audited_admin_review(client):
    teacher, parent, student, other, admin = [await auth(client,i) for i in [2,4,3,5,1]]
    ids = {u['id'] for u in (await client.get('/api/contacts',headers=teacher)).json()}
    assert {1,3,4} <= ids and 5 not in ids
    for recipient in [3,4,1]:
        assert (await client.post('/api/messages',json={'recipient_id':recipient,'text':'Lesson update'},headers=teacher)).status_code == 201
    assert (await client.post('/api/messages',json={'recipient_id':5,'text':'Not linked'},headers=teacher)).status_code == 404
    for unauthorized in [teacher,parent,student,other]:
        assert (await client.get('/api/admin/conversations',headers=unauthorized)).status_code == 403
        assert (await client.get('/api/admin/conversations/2/3',headers=unauthorized)).status_code == 403
    pairs = await client.get('/api/admin/conversations',headers=admin)
    assert pairs.status_code == 200, pairs.text
    assert len(pairs.json()) == 2
    assert all(c['count']==1 for c in pairs.json())
    thread = (await client.get('/api/admin/conversations/2/3',headers=admin)).json()
    assert thread[0]['text']=='Lesson update'
    assert (await client.get(f"/api/admin/conversations/2/3?before_id={thread[0]['id']}",headers=admin)).json()==[]
    assert (await client.get('/api/messages/3',headers=admin)).json()==[]
    async with client.factory() as db:
        actions = (await db.scalars(select(AuditLog.action))).all()
        assert 'review conversation 2:3' in actions
