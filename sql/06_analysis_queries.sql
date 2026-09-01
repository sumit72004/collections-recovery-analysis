/* 06_analysis_queries.sql — reproducible checks and executive analyses. */

-- 1) Quantify the reported 11% movement: Feb → Mar.
select
  max(recovery) filter(where month_start=date '2026-02-01') as feb_recovery,
  max(recovery) filter(where month_start=date '2026-03-01') as mar_recovery,
  (max(recovery) filter(where month_start=date '2026-03-01') /
   nullif(max(recovery) filter(where month_start=date '2026-02-01'),0)-1) as feb_mar_growth
from metrics.monthly;

-- 2) Decompose cash growth into payer count vs recovery per payer.
with x as (
 select month_start, payer_accounts, recovery_per_payer
 from metrics.monthly where month_start in (date '2026-02-01',date '2026-03-01')
)
select * from x order by month_start;

-- 3) Data-quality impact: duplicate successful payment IDs removed by payment-event deduplication.
with raw as (
 select count(*) rows, sum(amount) amount from raw.payments where payment_status='SUCCESS'
), cleanp as (
 select count(*) rows, sum(amount) amount from clean.payments where payment_status='SUCCESS'
)
select raw.rows as raw_success_rows, cleanp.rows as dedup_success_rows,
       raw.amount-cleanp.amount as cash_removed_by_dedup,
       (raw.rows-cleanp.rows) as success_rows_removed
from raw, cleanp;

-- 4) Attribution-window sensitivity: recovery within 1/7/14/30 days of first monthly target.
with first_target as (
 select account_id, date_trunc('month',min(target_date))::date month_start, min(target_date) target_date
 from clean.daily_targeting group by 1
), p as (
 select account_id,event_at::date payment_date,amount
 from clean.payments where payment_status='SUCCESS'
), s as (
 select ft.month_start, ft.account_id,
   sum(p.amount) filter(where p.payment_date between ft.target_date and ft.target_date+1) as r1,
   sum(p.amount) filter(where p.payment_date between ft.target_date and ft.target_date+7) as r7,
   sum(p.amount) filter(where p.payment_date between ft.target_date and ft.target_date+14) as r14,
   sum(p.amount) filter(where p.payment_date between ft.target_date and ft.target_date+30) as r30
 from first_target ft left join p on p.account_id=ft.account_id group by 1,2
)
select month_start, sum(r1) r1, sum(r7) r7, sum(r14) r14, sum(r30) r30
from s group by 1 order by 1;

-- 5) Selection bias: targeted vs never targeted among comparable month-account observations.
select ever_targeted_flag, month_start,
       count(*) accounts,
       avg(recovered_amount) recovery_per_account,
       avg(payer_flag::numeric) payer_rate,
       avg(case when outstanding_amount>0 then recovered_amount/outstanding_amount end) recovery_rate_proxy
from feat.account_month_enriched
group by 1,2 order by 2,1;

-- 6) Simpson's-paradox / mix check: overall vs DPD-stratified recovery.
select month_start, dpd,
       count(*) accounts, sum(recovered_amount) recovery,
       avg(case when outstanding_amount>0 then recovered_amount/outstanding_amount end) recovery_rate
from feat.account_month
group by 1,2 order by 1,2;

-- 7) Cohort effects: first-target month cohorts tracked over tenure.
select date_trunc('month', first_target_date)::date as target_cohort_month,
       months_since_first_target,
       count(*) accounts,
       avg(recovered_amount) recovery_per_account,
       avg(payer_flag::numeric) payer_rate
from feat.account_month_enriched
where first_target_date is not null and months_since_first_target between 0 and 5
group by 1,2 order by 1,2;

-- 8) Survivorship / denominator check: accounts disappearing from month population.
with pop as (
 select month_start,count(distinct account_id) n
 from gold.account_month group by 1
), paid as (
 select month_start,count(distinct account_id) paid_accounts
 from gold.account_month where recovered_amount>0 group by 1
)
select pop.month_start,pop.n,paid.paid_accounts,paid.paid_accounts::numeric/nullif(pop.n,0) payer_rate
from pop left join paid using(month_start) order by 1;

-- 9) Calling time: answered rate and recovery after hour normalization.
select month_start, local_hour,
       sum(calls) calls, sum(answered_calls) answered,
       sum(answered_calls)::numeric/nullif(sum(calls),0) contact_rate
from feat.call_hour group by 1,2 order by 1,2;

-- 10) Agent tenure analysis using employee identity + joined_at.
with agent_tenure as (
 select am.month_start, ai.employee_code, ai.canonical_agent_id,
        extract(day from (am.month_start - date_trunc('month',min(ai.joined_at))))/30.0 as tenure_months
 from clean.agent_identity ai
 cross join (select distinct month_start from gold.account_month) am
 group by am.month_start, ai.employee_code, ai.canonical_agent_id
), perf as (
 select c.month_start, ai.employee_code,
        sum(c.duration_sec)/3600.0 handled_hours,
        count(distinct case when c.call_status='ANSWERED' then c.call_id end) answered_calls,
        sum(g.recovered_amount) recovery
 from clean.calls c
 left join clean.agent_identity ai on ai.agent_id=c.agent_id
 left join gold.account_month g on g.account_id=c.account_id and g.month_start=date_trunc('month',c.event_at_utc)::date
 group by 1,2
)
select case when t.tenure_months<3 then '<3m' when t.tenure_months<6 then '3-6m'
            when t.tenure_months<12 then '6-12m' else '12m+' end tenure_band,
       sum(p.recovery) recovery, sum(p.handled_hours) handled_hours,
       sum(p.recovery)/nullif(sum(p.handled_hours),0) recovery_per_agent_hour
from perf p join agent_tenure t
  on t.employee_code=p.employee_code and t.month_start=p.month_start
 group by 1 order by 1;

-- 11) Telephony vendor stability: status/disposition performance by vendor and month.
select date_trunc('month',c.event_at_utc)::date month_start,
       c.vendor_id, v.vendor_name,
       count(*) calls, count(*) filter(where c.call_status='ANSWERED') answered,
       count(d.disposition_id) dispositions,
       count(d.disposition_id) filter(where d.call_answered_flag) answered_dispositions
from clean.calls c
left join clean.vendor_telephony v using(vendor_id)
left join clean.call_dispositions d using(call_id)
group by 1,2,3 order by 1,2;

-- 12) Channel conversion: target → recovery within 14 days.
select * from metrics.channel_14d order by recovery_14d desc nulls last;
