/* 02_cleaning.sql — Conformance, deduplication, identity resolution and quarantine. */
create schema if not exists clean;

-- Canonical account dimension. accounts is authoritative for account→borrower.
create or replace table clean.accounts as
select distinct on (account_id)
  account_id, borrower_id_raw as borrower_id, loan_type, principal_amount,
  outstanding_amount, dpd, risk_segment, status, opened_at, timezone, schema_version
from stg.accounts
where account_id is not null
order by account_id, schema_version desc, opened_at desc nulls last;

create or replace table clean.borrowers as
select distinct on (borrower_id)
  borrower_id, borrower_name, phone, email, city, state, created_at, updated_at
from stg.borrowers
where borrower_id is not null
order by borrower_id, updated_at desc nulls last;

-- Agent identity bridge: employee_code is the business identity when multiple technical agent_ids exist.
create or replace table clean.agent_identity as
select
  agent_id, employee_code, agent_name, vendor_id, team, status, joined_at, updated_at,
  first_value(agent_id) over (partition by employee_code order by updated_at desc nulls last, agent_id) as canonical_agent_id
from stg.agents
where agent_id is not null;

create or replace table clean.calls as
with ranked as (
  select c.*, row_number() over (
    partition by call_id order by event_at_local desc, duration_sec desc, agent_id_raw
  ) as rn
  from stg.calls c where call_id is not null
), conformed as (
  select r.call_id, r.account_id, a.borrower_id,
         r.event_at_local at time zone coalesce(r.timezone,'Asia/Kolkata') as event_at_utc,
         r.agent_id_raw as agent_id, r.campaign_id, r.direction, r.vendor_id_raw as vendor_id,
         r.call_status, r.duration_sec, r.timezone
  from ranked r left join clean.accounts a using(account_id)
  where rn=1
)
select * from conformed;

create or replace table clean.call_attempts as
with ranked as (
  select a.*, row_number() over (partition by attempt_id order by event_at_local desc, attempt_no desc) rn
  from stg.call_attempts a where attempt_id is not null
)
select r.attempt_id, r.account_id, a.borrower_id,
       r.event_at_local, r.call_id, r.agent_id_raw as agent_id, r.attempt_no,
       r.vendor_id_raw as vendor_id, r.attempt_status
from ranked r left join clean.accounts a using(account_id) where rn=1;

create or replace table clean.call_dispositions as
with mapped as (
  select d.*, c.call_status,
         case
           when d.disposition_code_raw in ('RPC','RIGHT_PARTY_CONTACT','CONTACTED') then 'RPC'
           when d.disposition_code_raw in ('PTP','PROMISE_TO_PAY') then 'PTP'
           when d.disposition_code_raw in ('WRONG_NUMBER','INVALID') then 'WRONG_PARTY'
           when d.disposition_code_raw in ('CALLBACK','CALL_BACK') then 'CALLBACK'
           else 'OTHER'
         end as disposition_code_std,
         row_number() over (partition by disposition_id order by d.event_at_local desc) rn
  from stg.call_dispositions d left join clean.calls c using(call_id)
)
select m.disposition_id, m.account_id, a.borrower_id, m.event_at_local,
       m.call_id, m.agent_id_raw as agent_id, m.disposition_code_raw,
       m.disposition_code_std, m.disposition_version,
       case when upper(coalesce(m.call_status,''))='ANSWERED' then true else false end as call_answered_flag
from mapped m left join clean.accounts a using(account_id) where rn=1;

/* Payment deduplication: do not use payment_reference as a global key.
   A payment_id is the primary event key; repeated successful rows with the same ID are one event.
   A repeated reference across different payment_ids is retained and flagged for review.
*/
create or replace table clean.payments as
with ranked as (
  select p.*, row_number() over (
    partition by payment_id order by event_at desc, recorded_at nulls last
  ) rn
  from (
    select s.*, null::timestamp as recorded_at from stg.payments s
  ) p where payment_id is not null
)
select r.payment_id, r.account_id, a.borrower_id, r.event_at,
       r.payment_reference, r.amount, r.payment_status, r.payment_method, r.provider_id,
       case when count(*) over(partition by payment_reference)>1 then true else false end as repeated_reference_flag
from ranked r left join clean.accounts a using(account_id)
where rn=1;

create or replace table clean.daily_targeting as
select
  t.target_id, t.account_id, a.borrower_id, t.campaign_id, t.target_date,
  t.priority, t.recommended_channel, t.status,
  c.channel as campaign_channel, c.strategy_version
from stg.daily_targeting t
left join clean.accounts a using(account_id)
left join stg.campaigns c using(campaign_id)
where t.target_id is not null;

create or replace table clean.promises_to_pay as
select distinct on (ptp_id)
  p.ptp_id, p.account_id, a.borrower_id, p.event_at_local as event_at,
  p.agent_id_raw as agent_id, p.promised_amount, p.promised_date, p.status, p.source
from stg.promises_to_pay p
left join clean.accounts a using(account_id)
where ptp_id is not null
order by ptp_id, event_at_local desc;

create or replace table clean.whatsapp_events as
select distinct on (whatsapp_event_id)
  e.whatsapp_event_id, e.account_id, a.borrower_id, e.event_at, e.message_id,
  e.event_type, e.template_code, e.provider_id
from stg.whatsapp_events e left join clean.accounts a using(account_id)
where whatsapp_event_id is not null
order by whatsapp_event_id, event_at desc;

create or replace table clean.sms_events as
select distinct on (sms_event_id)
  e.sms_event_id, e.account_id, a.borrower_id, e.event_at, e.message_id,
  e.event_type, e.template_code, e.provider_id
from stg.sms_events e left join clean.accounts a using(account_id)
where sms_event_id is not null
order by sms_event_id, event_at desc;

create or replace table clean.field_visits as
select distinct on (visit_id)
  v.visit_id, v.account_id, a.borrower_id, v.event_at, v.agent_id_raw as agent_id,
  v.visit_type, v.outcome, v.latitude, v.longitude, v.scheduled_at
from stg.field_visits v left join clean.accounts a using(account_id)
where visit_id is not null
order by visit_id, event_at desc;

create or replace table clean.agent_sessions as
select distinct on (session_id) *
from stg.agent_sessions
where session_id is not null
order by session_id, login_at desc;

create or replace table clean.status_history as
select distinct on (history_id)
  h.history_id, h.account_id, a.borrower_id, h.event_at, h.status, h.changed_by,
  h.source, h.recorded_at
from stg.account_status_history h left join clean.accounts a using(account_id)
where history_id is not null
order by history_id, recorded_at desc nulls last, event_at desc;

create or replace table clean.complaints as
select distinct on (complaint_id)
  c.complaint_id, c.account_id, a.borrower_id, c.event_at, c.complaint_type,
  c.severity, c.status, c.source, c.resolution_at
from stg.complaints c left join clean.accounts a using(account_id)
where complaint_id is not null
order by complaint_id, event_at desc;

create or replace table clean.dq_account_borrower_conflicts as
select 'calls' as source, count(*) as conflict_rows
from stg.calls c join clean.accounts a using(account_id)
where c.borrower_id_raw is distinct from a.borrower_id
union all select 'payments', count(*) from stg.payments p join clean.accounts a using(account_id)
where p.borrower_id_raw is distinct from a.borrower_id
union all select 'call_attempts', count(*) from stg.call_attempts x join clean.accounts a using(account_id)
where x.borrower_id_raw is distinct from a.borrower_id;

create or replace table clean.quarantine_orphans as
select 'CALL' source, c.call_id event_id, c.account_id from stg.calls c left join clean.accounts a using(account_id) where a.account_id is null
union all select 'PAYMENT', p.payment_id, p.account_id from stg.payments p left join clean.accounts a using(account_id) where a.account_id is null
union all select 'ATTEMPT', x.attempt_id, x.account_id from stg.call_attempts x left join clean.accounts a using(account_id) where a.account_id is null;
