/* 03_golden_dataset.sql — one row per account per calendar month (UTC-normalized events). */
create schema if not exists gold;

create or replace table gold.account_month as
with months as (
  select generate_series(date '2026-01-01', date '2026-08-01', interval '1 month')::date as month_start
), base as (
  select a.account_id, a.borrower_id, a.loan_type, a.principal_amount,
         a.outstanding_amount, a.dpd, a.risk_segment, a.status as account_status,
         a.opened_at, a.timezone, m.month_start
  from clean.accounts a cross join months m
  where a.opened_at::date <= (m.month_start + interval '1 month - 1 day')::date
), payment as (
  select account_id,
         date_trunc('month', event_at)::date as month_start,
         sum(amount) filter (where payment_status='SUCCESS') as success_payment_amount,
         count(*) filter (where payment_status='SUCCESS') as success_payment_events,
         count(distinct payment_id) filter (where payment_status='SUCCESS') as success_payment_ids
  from clean.payments group by 1,2
), attempts as (
  select account_id, date_trunc('month', event_at_local)::date month_start,
         count(*) as attempts, count(distinct call_id) as attempted_calls
  from clean.call_attempts group by 1,2
), calls as (
  select account_id, date_trunc('month', event_at_utc)::date month_start,
         count(*) as calls, count(*) filter(where call_status='ANSWERED') as answered_calls,
         sum(duration_sec) filter(where call_status='ANSWERED') as answered_seconds,
         count(distinct campaign_id) as campaigns_touched
  from clean.calls group by 1,2
), rpc as (
  select account_id, date_trunc('month', event_at_local)::date month_start,
         count(*) filter(where disposition_code_std='RPC' and call_answered_flag) as rpc_events,
         count(*) filter(where disposition_code_std='PTP' and call_answered_flag) as ptp_events
  from clean.call_dispositions group by 1,2
), target as (
  select account_id, date_trunc('month', target_date)::date month_start,
         count(distinct target_id) as target_events,
         count(distinct campaign_id) as target_campaigns,
         max(target_date) as last_target_date
  from clean.daily_targeting group by 1,2
), ptp as (
  select account_id, date_trunc('month', event_at)::date month_start,
         count(*) as ptp_count, sum(promised_amount) as promised_amount,
         count(*) filter(where status='KEPT') as ptp_kept_count,
         sum(promised_amount) filter(where status='KEPT') as ptp_kept_amount
  from clean.promises_to_pay group by 1,2
), wa as (
  select account_id, date_trunc('month', event_at)::date month_start,
         count(*) as whatsapp_events,
         count(*) filter(where event_type in ('DELIVERED','READ','CLICKED')) as whatsapp_engaged
  from clean.whatsapp_events group by 1,2
), sms as (
  select account_id, date_trunc('month', event_at)::date month_start,
         count(*) as sms_events,
         count(*) filter(where event_type in ('DELIVERED','CLICKED')) as sms_engaged
  from clean.sms_events group by 1,2
), fv as (
  select account_id, date_trunc('month', event_at)::date month_start,
         count(*) as field_visits,
         count(*) filter(where outcome='PAID') as paid_field_visits
  from clean.field_visits group by 1,2
), complaints as (
  select account_id, date_trunc('month', event_at)::date month_start,
         count(*) as complaints
  from clean.complaints group by 1,2
)
select
  b.*,
  coalesce(p.success_payment_amount,0)::numeric(18,2) as recovered_amount,
  coalesce(p.success_payment_events,0) as success_payment_events,
  coalesce(p.success_payment_ids,0) as success_payment_ids,
  coalesce(x.attempts,0) as attempts,
  coalesce(x.attempted_calls,0) as attempted_calls,
  coalesce(c.calls,0) as calls,
  coalesce(c.answered_calls,0) as answered_calls,
  coalesce(c.answered_seconds,0) as answered_seconds,
  coalesce(c.campaigns_touched,0) as campaigns_touched,
  coalesce(r.rpc_events,0) as rpc_events,
  coalesce(r.ptp_events,0) as ptp_events,
  coalesce(t.target_events,0) as target_events,
  coalesce(t.target_campaigns,0) as target_campaigns,
  t.last_target_date,
  coalesce(pt.ptp_count,0) as ptp_count,
  coalesce(pt.promised_amount,0)::numeric(18,2) as promised_amount,
  coalesce(pt.ptp_kept_count,0) as ptp_kept_count,
  coalesce(pt.ptp_kept_amount,0)::numeric(18,2) as ptp_kept_amount,
  coalesce(w.whatsapp_events,0) as whatsapp_events,
  coalesce(w.whatsapp_engaged,0) as whatsapp_engaged,
  coalesce(s.sms_events,0) as sms_events,
  coalesce(s.sms_engaged,0) as sms_engaged,
  coalesce(f.field_visits,0) as field_visits,
  coalesce(f.paid_field_visits,0) as paid_field_visits,
  coalesce(co.complaints,0) as complaints
from base b
left join payment p using(account_id,month_start)
left join attempts x using(account_id,month_start)
left join calls c using(account_id,month_start)
left join rpc r using(account_id,month_start)
left join target t using(account_id,month_start)
left join ptp pt using(account_id,month_start)
left join wa w using(account_id,month_start)
left join sms s using(account_id,month_start)
left join fv f using(account_id,month_start)
left join complaints co using(account_id,month_start);

create unique index if not exists ux_gold_account_month on gold.account_month(account_id, month_start);
