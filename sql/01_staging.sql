/*
01_staging.sql — Raw-to-staging layer (PostgreSQL)
Purpose: preserve source records, standardize types, and surface source-system quality flags.
Load convention: raw.<table_name> mirrors the supplied CSV column names.
No business filtering occurs here.
*/

create schema if not exists stg;

create or replace view stg.accounts as
select
  trim(account_id) as account_id,
  nullif(trim(borrower_id), '') as borrower_id_raw,
  upper(trim(loan_type)) as loan_type,
  principal_amount::numeric(18,2) as principal_amount,
  outstanding_amount::numeric(18,2) as outstanding_amount,
  dpd::integer as dpd,
  upper(trim(risk_segment)) as risk_segment,
  upper(trim(status)) as status,
  opened_at::timestamp as opened_at,
  trim(timezone) as timezone,
  lower(trim(schema_version)) as schema_version
from raw.accounts;

create or replace view stg.borrowers as
select
  trim(borrower_id) as borrower_id,
  nullif(trim(name), '') as borrower_name,
  nullif(trim(phone), '') as phone,
  nullif(lower(trim(email)), '') as email,
  nullif(trim(city), '') as city,
  nullif(trim(state), '') as state,
  created_at::timestamp as created_at,
  updated_at::timestamp as updated_at
from raw.borrowers;

create or replace view stg.agents as
select
  trim(agent_id) as agent_id,
  trim(employee_code) as employee_code,
  nullif(trim(agent_name), '') as agent_name,
  trim(vendor_id) as vendor_id,
  nullif(trim(team), '') as team,
  upper(trim(status)) as status,
  joined_at::timestamp as joined_at,
  updated_at::timestamp as updated_at
from raw.agents;

create or replace view stg.payments as
select
  trim(payment_id) as payment_id,
  trim(account_id) as account_id,
  trim(borrower_id) as borrower_id_raw,
  event_at::timestamp as event_at,
  trim(payment_reference) as payment_reference,
  amount::numeric(18,2) as amount,
  upper(trim(payment_status)) as payment_status,
  upper(trim(payment_method)) as payment_method,
  trim(provider_id) as provider_id
from raw.payments;

create or replace view stg.calls as
select
  trim(call_id) as call_id,
  trim(account_id) as account_id,
  trim(borrower_id) as borrower_id_raw,
  event_at::timestamp as event_at_local,
  trim(agent_id) as agent_id_raw,
  trim(campaign_id) as campaign_id,
  upper(trim(direction)) as direction,
  trim(vendor_id) as vendor_id_raw,
  upper(trim(call_status)) as call_status,
  coalesce(duration_sec,0)::integer as duration_sec,
  trim(timezone) as timezone
from raw.calls;

create or replace view stg.call_attempts as
select
  trim(attempt_id) as attempt_id,
  trim(account_id) as account_id,
  trim(borrower_id) as borrower_id_raw,
  event_at::timestamp as event_at_local,
  trim(call_id) as call_id,
  trim(agent_id) as agent_id_raw,
  attempt_no::integer as attempt_no,
  trim(vendor_id) as vendor_id_raw,
  upper(trim(attempt_status)) as attempt_status
from raw.call_attempts;

create or replace view stg.call_dispositions as
select
  trim(disposition_id) as disposition_id,
  trim(account_id) as account_id,
  trim(borrower_id) as borrower_id_raw,
  event_at::timestamp as event_at_local,
  trim(call_id) as call_id,
  trim(agent_id) as agent_id_raw,
  upper(trim(disposition_code)) as disposition_code_raw,
  lower(trim(disposition_version)) as disposition_version
from raw.call_dispositions;

create or replace view stg.daily_targeting as
select
  trim(target_id) as target_id,
  trim(account_id) as account_id,
  trim(campaign_id) as campaign_id,
  target_date::date as target_date,
  priority::integer as priority,
  upper(trim(recommended_channel)) as recommended_channel,
  upper(trim(status)) as status
from raw.daily_targeting;

create or replace view stg.campaigns as
select
  trim(campaign_id) as campaign_id,
  nullif(trim(campaign_name),'') as campaign_name,
  upper(trim(channel)) as channel,
  nullif(trim(strategy_version),'') as strategy_version,
  start_at::timestamp as start_at,
  nullif(trim(target_definition),'') as target_definition,
  end_at::timestamp as end_at
from raw.campaigns;

create or replace view stg.promises_to_pay as
select
  trim(ptp_id) as ptp_id,
  trim(account_id) as account_id,
  trim(borrower_id) as borrower_id_raw,
  event_at::timestamp as event_at_local,
  trim(agent_id) as agent_id_raw,
  promised_amount::numeric(18,2) as promised_amount,
  promised_date::timestamp as promised_date,
  upper(trim(status)) as status,
  upper(trim(source)) as source
from raw.promises_to_pay;

create or replace view stg.whatsapp_events as
select trim(whatsapp_event_id) as whatsapp_event_id, trim(account_id) as account_id,
       trim(borrower_id) as borrower_id_raw, event_at::timestamp as event_at,
       trim(message_id) as message_id, upper(trim(event_type)) as event_type,
       nullif(trim(template_code),'') as template_code, trim(provider_id) as provider_id
from raw.whatsapp_events;

create or replace view stg.sms_events as
select trim(sms_event_id) as sms_event_id, trim(account_id) as account_id,
       trim(borrower_id) as borrower_id_raw, event_at::timestamp as event_at,
       trim(message_id) as message_id, upper(trim(event_type)) as event_type,
       nullif(trim(template_code),'') as template_code, trim(provider_id) as provider_id
from raw.sms_events;

create or replace view stg.field_visits as
select trim(visit_id) as visit_id, trim(account_id) as account_id,
       trim(borrower_id) as borrower_id_raw, event_at::timestamp as event_at,
       trim(agent_id) as agent_id_raw, upper(trim(visit_type)) as visit_type,
       upper(trim(outcome)) as outcome, latitude::numeric as latitude,
       longitude::numeric as longitude, scheduled_at::timestamp as scheduled_at
from raw.field_visits;

create or replace view stg.agent_sessions as
select trim(session_id) as session_id, trim(agent_id) as agent_id,
       login_at::timestamp as login_at, upper(trim(channel)) as channel,
       nullif(trim(device_id),'') as device_id, trim(timezone) as timezone,
       logout_at::timestamp as logout_at
from raw.agent_sessions;

create or replace view stg.account_status_history as
select trim(history_id) as history_id, trim(account_id) as account_id,
       trim(borrower_id) as borrower_id_raw, event_at::timestamp as event_at,
       upper(trim(status)) as status, nullif(trim(changed_by),'') as changed_by,
       upper(trim(source)) as source, recorded_at::timestamp as recorded_at
from raw.account_status_history;

create or replace view stg.complaints as
select trim(complaint_id) as complaint_id, trim(account_id) as account_id,
       trim(borrower_id) as borrower_id_raw, event_at::timestamp as event_at,
       upper(trim(complaint_type)) as complaint_type, upper(trim(severity)) as severity,
       upper(trim(status)) as status, upper(trim(source)) as source,
       resolution_at::timestamp as resolution_at
from raw.complaints;

create or replace view stg.vendor_telephony as
select trim(vendor_id) as vendor_id, nullif(trim(vendor_name),'') as vendor_name,
       nullif(trim(vendor_account_id),'') as vendor_account_id,
       trim(timezone) as timezone, upper(trim(status)) as status,
       lower(trim(schema_version)) as schema_version
from raw.vendor_telephony;
