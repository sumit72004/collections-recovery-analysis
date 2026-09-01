/* 04_features.sql — reusable features for targeting, cohort and channel analysis. */
create schema if not exists feat;

create or replace table feat.account_month as
select
  g.*,
  extract(day from (month_start + interval '1 month - 1 day'))::integer as days_in_month,
  case when recovered_amount > 0 then 1 else 0 end as payer_flag,
  case when calls > 0 then 1 else 0 end as attempted_flag,
  case when answered_calls > 0 then 1 else 0 end as contact_flag,
  case when rpc_events > 0 then 1 else 0 end as rpc_flag,
  case when ptp_count > 0 then 1 else 0 end as ptp_flag,
  case when target_events > 0 then 1 else 0 end as targeted_flag,
  case when field_visits > 0 then 1 else 0 end as field_contact_flag,
  case when whatsapp_engaged + sms_engaged > 0 then 1 else 0 end as digital_engaged_flag,
  case when ptp_count > 0 then ptp_kept_count::numeric / ptp_count else null end as ptp_kept_rate,
  case when calls > 0 then answered_calls::numeric / calls else null end as contact_rate,
  case when answered_calls > 0 then rpc_events::numeric / answered_calls else null end as rpc_rate,
  case when answered_calls > 0 then ptp_count::numeric / answered_calls else null end as ptp_rate,
  case when account_id is not null then recovered_amount::numeric / nullif(outstanding_amount,0) end as recovery_rate_proxy,
  case when attempts > 0 then recovered_amount::numeric / attempts else null end as recovery_per_attempt,
  case when answered_seconds > 0 then recovered_amount::numeric / (answered_seconds/3600.0) else null end as recovery_per_answered_hour
from gold.account_month g;

-- First observed targeting month for each account; useful for treatment definition without post-treatment leakage.
create or replace table feat.targeting_cohort as
select account_id, min(target_date)::date as first_target_date
from clean.daily_targeting
group by 1;

create or replace table feat.account_month_enriched as
select f.*, tc.first_target_date,
       case when f.targeted_flag=1 or tc.first_target_date is not null then 1 else 0 end as ever_targeted_flag,
       case when tc.first_target_date is not null and f.month_start >= date_trunc('month',tc.first_target_date)::date then 1 else 0 end as post_first_target_flag,
       extract(month from (f.month_start - date_trunc('month',tc.first_target_date)))::integer as months_since_first_target
from feat.account_month f left join feat.targeting_cohort tc using(account_id);

-- Calling-time features in the caller-local timezone.
create or replace table feat.call_hour as
select
  account_id,
  date_trunc('month', event_at_utc)::date as month_start,
  extract(hour from (event_at_utc at time zone coalesce(timezone,'Asia/Kolkata')))::integer as local_hour,
  count(*) as calls,
  count(*) filter(where call_status='ANSWERED') as answered_calls,
  sum(duration_sec) filter(where call_status='ANSWERED') as answered_seconds
from clean.calls
group by 1,2,3;

-- Agent-hour bridge based on logged-in duration. Used as a workforce productivity denominator, not a causal outcome.
create or replace table feat.agent_month as
select
  date_trunc('month', login_at)::date as month_start,
  ai.employee_code,
  ai.canonical_agent_id,
  s.channel,
  sum(extract(epoch from (coalesce(logout_at, login_at)-login_at))/3600.0) as logged_hours,
  count(distinct session_id) as sessions
from clean.agent_sessions s
left join clean.agent_identity ai on ai.agent_id=s.agent_id
group by 1,2,3,4;
