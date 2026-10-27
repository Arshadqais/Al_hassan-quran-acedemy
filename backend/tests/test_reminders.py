import asyncio
import hashlib
import hmac
import json
from datetime import timedelta
import httpx
import pytest
from sqlalchemy import select
from app import reminders
from app.models import ClassSession, Enrollment, ReminderContact, WhatsAppReminder, now
from app.whatsapp_setup import verify_whatsapp, save_whatsapp
from conftest import auth

CONFIG = {
    'WHATSAPP_PHONE_NUMBER_ID':'12345', 'WHATSAPP_WABA_ID':'67890',
    'WHATSAPP_ACCESS_TOKEN':'test-token-not-real', 'WHATSAPP_TEMPLATE_NAME':'class_reminder',
    'WHATSAPP_TEMPLATE_LANGUAGE':'en', 'WHATSAPP_API_VERSION':'v23.0',
    'WHATSAPP_APP_SECRET':'test-app-secret', 'WHATSAPP_VERIFY_TOKEN':'test-verify-token',
    'REMINDER_MINUTES':'10', 'REMINDER_TIMEZONE':'Asia/Karachi',
}


async def seed(client):
    current=now()
    async with client.factory() as db:
        for user in [2,3,4,5,6]:
            db.add(ReminderContact(user_id=user,phone=f'+92300123000{user}',consent=True))
        lesson=ClassSession(title='Quran lesson',teacher_id=2,starts_at=current+timedelta(minutes=8),duration=30)
        db.add(lesson)
        await db.flush()
        db.add(Enrollment(session_id=lesson.id,student_id=3))
        await db.commit()
        return lesson.id,current


@pytest.mark.asyncio
async def test_opt_in_is_own_only_and_numbers_are_not_public(client):
    teacher=await auth(client,2)
    assert (await client.get('/api/auth/reminder-contact')).status_code==401
    assert (await client.get('/api/auth/reminder-contact',headers=teacher)).json()=={'phone':'','consent':False}
    for data in [{'phone':'1122','consent':True},{'phone':'','consent':True},{'phone':'+00001234567','consent':True}]:
        assert (await client.put('/api/auth/reminder-contact',json=data,headers=teacher)).status_code==422
    assert (await client.put('/api/auth/reminder-contact',json={'phone':'+923001234567','consent':True},headers=teacher)).status_code==200
    assert '923001234567' not in (await client.get('/api/users',headers=teacher)).text
    assert (await client.get('/api/admin/reminders',headers=teacher)).status_code==403
    parent=await auth(client,4)
    assert (await client.get('/api/auth/reminder-contact',headers=parent)).json()['phone']==''


@pytest.mark.asyncio
async def test_due_window_routing_and_durable_deduplication(client):
    ident,current=await seed(client)
    async with client.factory() as db:
        for offset,cancelled in [(11,False),(-1,False),(5,True)]:
            lesson=ClassSession(title='Not due',teacher_id=2,starts_at=current+timedelta(minutes=offset),cancelled=cancelled)
            db.add(lesson);await db.flush();db.add(Enrollment(session_id=lesson.id,student_id=3))
        await db.commit()
        assert await reminders.queue_reminders(db,None,current)==0
        assert await reminders.queue_reminders(db,reminders.settings(CONFIG),current)==3
    async with client.factory() as db:
        assert await reminders.queue_reminders(db,reminders.settings(CONFIG),current)==0
        rows=(await db.scalars(select(WhatsAppReminder))).all()
        assert {r.user_id for r in rows}=={2,3,4}
        assert all(r.session_id==ident for r in rows)
        contact=await db.get(ReminderContact,3)
        contact.phone='+923009999999';await db.commit()
        assert await reminders.queue_reminders(db,reminders.settings(CONFIG),current)==0


@pytest.mark.asyncio
async def test_shared_family_phone_receives_one_message_per_class(client):
    ident,current=await seed(client)
    async with client.factory() as db:
        (await db.get(ReminderContact,4)).phone='+923001230003'
        await db.commit()
        assert await reminders.queue_reminders(db,reminders.settings(CONFIG),current)==2


@pytest.mark.asyncio
async def test_opt_out_cancellation_and_provider_template_payload(client):
    ident,current=await seed(client)
    config=reminders.settings(CONFIG)
    async with client.factory() as db:
        await reminders.queue_reminders(db,config,current)
        (await db.get(ReminderContact,2)).consent=False
        await db.commit()
    calls=[]
    def send(request):
        body=json.loads(request.content);calls.append(body)
        assert request.url.host=='graph.facebook.com'
        assert request.headers['Authorization']=='Bearer test-token-not-real'
        assert body['template']['components'][0]['parameters'][0]['text']=='Quran lesson'
        assert '(Asia/Karachi)' in body['template']['components'][0]['parameters'][1]['text']
        return httpx.Response(200,json={'messages':[{'id':'wamid.'+body['to']}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(send)) as http:
        for _ in range(3):assert await reminders.dispatch_one(client.factory,http,config,current)
        assert not await reminders.dispatch_one(client.factory,http,config,current)
    assert {c['to'] for c in calls}=={'923001230003','923001230004'}
    async with client.factory() as db:
        rows=(await db.scalars(select(WhatsAppReminder))).all()
        assert {r.state for r in rows}=={'skipped','accepted'}
        assert await reminders.queue_reminders(db,config,current)==0
    admin=await auth(client,1)
    status=(await client.get('/api/admin/reminders',headers=admin)).json()
    assert all(len(r['phone'])==8 for r in status['deliveries'])
    assert '923001230003' not in json.dumps(status)


@pytest.mark.asyncio
async def test_retry_only_unambiguous_rejection_and_never_after_class_start(client):
    ident,current=await seed(client)
    config=reminders.settings(CONFIG)
    async with client.factory() as db:
        (await db.get(ReminderContact,3)).consent=False
        (await db.get(ReminderContact,4)).consent=False
        await db.commit();await reminders.queue_reminders(db,config,current)
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(429))) as http:
        await reminders.dispatch_one(client.factory,http,config,current)
        assert not await reminders.dispatch_one(client.factory,http,config,current+timedelta(seconds=30))
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={'messages':[{'id':'wamid.retry'}]}))) as http:
        await reminders.dispatch_one(client.factory,http,config,current+timedelta(seconds=61))
    async with client.factory() as db:
        row=await db.scalar(select(WhatsAppReminder))
        assert row.state=='accepted' and row.attempts==2
        row.state='pending';row.next_attempt_at=current;await db.commit()
    calls=[]
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:calls.append(r) or httpx.Response(200))) as http:
        await reminders.dispatch_one(client.factory,http,config,current+timedelta(minutes=9))
    assert calls==[]
    async with client.factory() as db:assert (await db.scalar(select(WhatsAppReminder))).state=='skipped'


@pytest.mark.asyncio
async def test_uncertain_network_result_is_not_automatically_resent(client):
    ident,current=await seed(client);config=reminders.settings(CONFIG)
    async with client.factory() as db:
        (await db.get(ReminderContact,3)).consent=False;(await db.get(ReminderContact,4)).consent=False
        await db.commit();await reminders.queue_reminders(db,config,current)
    def timeout(request):raise httpx.ReadTimeout('Synthetic timeout')
    async with httpx.AsyncClient(transport=httpx.MockTransport(timeout)) as http:
        assert await reminders.dispatch_one(client.factory,http,config,current)
        assert not await reminders.dispatch_one(client.factory,http,config,current)
    async with client.factory() as db:
        row=await db.scalar(select(WhatsAppReminder));assert row.state=='unknown'
        row.state='sending';row.claimed_at=current-timedelta(minutes=3);await db.commit()
        await reminders.recover_uncertain(db,current)
        assert row.state=='unknown' and row.error_code=='interrupted_result_unknown'


def receipt(message_id,status,callback=None):
    entry={'id':message_id,'status':status}
    if callback:entry['biz_opaque_callback_data']=callback
    return {'object':'whatsapp_business_account','entry':[{'id':'67890','changes':[{'value':{
        'metadata':{'phone_number_id':'12345'},'statuses':[entry]}}]}]}


def signed(payload):
    raw=json.dumps(payload).encode()
    return raw,{'X-Hub-Signature-256':'sha256='+hmac.new(CONFIG['WHATSAPP_APP_SECRET'].encode(),raw,hashlib.sha256).hexdigest()}


@pytest.mark.asyncio
async def test_signed_delivery_receipts_are_ordered_and_verification_is_private(client,monkeypatch):
    monkeypatch.setattr(reminders,'configuration',lambda:dict(CONFIG))
    ident,current=await seed(client)
    async with client.factory() as db:
        db.add(WhatsAppReminder(session_id=ident,user_id=2,phone='+923001230002',starts_at=current,state='accepted',provider_id='wamid.test'))
        await db.commit()
    assert (await client.get('/api/whatsapp/webhook',params={'hub.mode':'subscribe','hub.verify_token':'test-verify-token','hub.challenge':'challenge'})).text=='challenge'
    assert (await client.get('/api/whatsapp/webhook',params={'hub.mode':'subscribe','hub.verify_token':'wrong'})).status_code==403
    raw,headers=signed(receipt('wamid.test','delivered'))
    assert (await client.post('/api/whatsapp/webhook',content=raw)).status_code==403
    assert (await client.post('/api/whatsapp/webhook',content=raw,headers=headers)).status_code==200
    for state in ['read','sent','failed']:
        raw,headers=signed(receipt('wamid.test',state))
        assert (await client.post('/api/whatsapp/webhook',content=raw,headers=headers)).status_code==200
    async with client.factory() as db:assert (await db.scalar(select(WhatsAppReminder))).state=='read'


@pytest.mark.asyncio
async def test_receipt_can_arrive_before_send_response_without_losing_status(client,monkeypatch):
    monkeypatch.setattr(reminders,'configuration',lambda:dict(CONFIG))
    ident,current=await seed(client);config=reminders.settings(CONFIG)
    async with client.factory() as db:
        (await db.get(ReminderContact,3)).consent=False;(await db.get(ReminderContact,4)).consent=False
        await db.commit();await reminders.queue_reminders(db,config,current)
    async def transport(request):
        body=json.loads(request.content)
        raw,headers=signed(receipt('wamid.early','delivered',body['biz_opaque_callback_data']))
        assert (await client.post('/api/whatsapp/webhook',content=raw,headers=headers)).status_code==200
        return httpx.Response(200,json={'messages':[{'id':'wamid.early'}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as http:
        await reminders.dispatch_one(client.factory,http,config,current)
    async with client.factory() as db:assert (await db.scalar(select(WhatsAppReminder))).state=='delivered'


@pytest.mark.asyncio
async def test_setup_checks_sender_and_approved_two_parameter_template_without_sending(tmp_path):
    calls=[]
    def transport(request):
        calls.append(request.method)
        if request.url.path.endswith('/phone_numbers'):return httpx.Response(200,json={'data':[{'id':'12345'}]})
        return httpx.Response(200,json={'data':[{'name':'class_reminder','language':'en','status':'APPROVED','components':[{'type':'BODY','text':'Class {{1}} starts {{2}}.'}]}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as http:
        assert (await verify_whatsapp(CONFIG,http))['minutes']==10
    assert calls==['GET','GET']
    path=tmp_path/'.env';path.write_text('DATABASE_PASSWORD=keep-this-test-value\n')
    save_whatsapp(path,CONFIG)
    assert 'DATABASE_PASSWORD=keep-this-test-value' in path.read_text()
    assert path.stat().st_mode&0o777==0o600
    with pytest.raises(ValueError):save_whatsapp(path,{**CONFIG,'WHATSAPP_ACCESS_TOKEN':'x\nDATABASE_PASSWORD=bad'})


@pytest.mark.asyncio
async def test_cancelled_class_is_rechecked_after_reminder_was_queued(client):
    ident,current=await seed(client);config=reminders.settings(CONFIG)
    async with client.factory() as db:
        await reminders.queue_reminders(db,config,current)
        (await db.get(ClassSession,ident)).cancelled=True
        await db.commit()
    calls=[]
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:calls.append(r) or httpx.Response(200))) as http:
        for _ in range(3):assert await reminders.dispatch_one(client.factory,http,config,current)
    assert calls==[]
    async with client.factory() as db:
        assert all(r.state=='skipped' for r in (await db.scalars(select(WhatsAppReminder))).all())


@pytest.mark.asyncio
async def test_reminder_worker_is_started_and_stopped_with_backend_lifespan(monkeypatch):
    from app import main
    started=asyncio.Event();closed=asyncio.Event()
    async def worker():
        started.set()
        try:await asyncio.Future()
        finally:closed.set()
    monkeypatch.setattr(main,'reminder_worker',worker)
    async with main.lifespan(main.app):
        await asyncio.wait_for(started.wait(),1)
    assert closed.is_set()


@pytest.mark.asyncio
async def test_family_number_change_after_queue_does_not_conflict_or_duplicate(client):
    ident,current=await seed(client);config=reminders.settings(CONFIG)
    async with client.factory() as db:
        await reminders.queue_reminders(db,config,current)
        (await db.get(ReminderContact,4)).phone='+923001230003'
        await db.commit()
    calls=[]
    def send(request):
        body=json.loads(request.content);calls.append(body['to'])
        return httpx.Response(200,json={'messages':[{'id':'wamid.'+body['to']}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(send)) as http:
        for _ in range(3):assert await reminders.dispatch_one(client.factory,http,config,current)
    assert sorted(calls)==['923001230002','923001230003']
