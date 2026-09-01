/* 05_metrics.sql — KPI definitions. All metrics are calculated from gold/feat layers. */
create schema if not exists metrics;

create or replace table metrics.monthly as
select
  month_start,
  sum(recovered_amount)::numeric(18,2) as recovery,
  count(distinct account_id) as accounts_in_population,
  count(distinct account_id) filter(where payer_flag=1) as payer_accounts,
  sum(recovered_amount) / nullif(count(distinct account_id),0) as recovery_per_account,
  sum(recovered_amount) / nullif(count(distinct account_id) filter(where payer_flag=1),0) as recovery_per_payer,
  sum(recovered_amount) / nullif(sum(outstanding_amount),0) as recovery_rate_proxy,
  count(distinct account_id) filter(where calls>0) as attempted_accounts,
  count(distinct account_id) filter(where answered_calls>0) as contacted_accounts,
  count(distinct account_id) filter(where rpc_flag=1) as rpc_accounts,
  count(distinct account_id) filter(where ptp_flag=1) as ptp_accounts,
  case when count(distinct account_id) filter(where calls>0)>0
       then count(distinct account_id) filter(where answered_calls>0)::numeric / count(distinct account_id) filter(where calls>0) end as contact_rate,
  case when count(distinct account_id) filter(where answered_calls>0)>0
       then count(distinct account_id) filter(where rpc_flag=1)::numeric / count(distinct account_id) filter(where answered_calls>0) end as rpc_rate,
  case when count(distinct account_id) filter(where answered_calls>0)>0
       then count(distinct account_id) filter(where ptp_flag=1)::numeric / count(distinct account_id) filter(where answered_calls>0) end as ptp_rate,
  case when sum(ptp_count)>0 then sum(ptp_kept_count)::numeric / sum(ptp_count) end as ptp_kept_rate,
  sum(answered_seconds)::numeric / 3600 as answered_agent_hours,
  sum(recovered_amount) / nullif(sum(answered_seconds)/3600.0,0) as recovery_per_answered_agent_hour
from feat.account_month
group by 1;

create or replace table metrics.channel_14d as
with target as (
  select distinct account_id, target_date, recommended_channel
  from clean.daily_targeting
), paid as (
  select p.account_id, p.event_at::date as payment_date, p.amount
  from clean.payments p where p.payment_status='SUCCESS'
), joined as (
  select t.account_id, t.target_date, t.recommended_channel,
         sum(p.amount) as recovered_14d
  from target t left join paid p on p.account_id=t.account_id
    and p.payment_date between t.target_date and t.target_date+14
  group by 1,2,3
)
select recommended_channel, count(*) as target_records,
       count(*) filter(where recovered_14d>0) as converting_target_records,
       sum(recovered_14d)::numeric(18,2) as recovery_14d,
       avg(recovered_14d) as recovery_per_target,
       avg(case when recovered_14d>0 then 1.0 else 0.0 end) as conversion_rate_14d
from joined
group by 1;

create or replace table metrics.investment_scenarios as
with run as (
  select avg(recovery) as avg_monthly_recovery from metrics.monthly where month_start < date '2026-08-01'
), scenarios as (
  select x.lift, x.lift*run.avg_monthly_recovery*12 as incremental_recovery,
         run.avg_monthly_recovery*12 as annualized_baseline
  from run cross join (values (0.02::numeric),(0.05::numeric),(0.08::numeric)) x(lift)
)
select lift, annualized_baseline, incremental_recovery,
       100000000::numeric as investment_cost,
       incremental_recovery/100000000 as gross_benefit_cost,
       (incremental_recovery-100000000)/100000000 as net_roi,
       100000000/nullif(annualized_baseline,0) as break_even_lift
from scenarios;
