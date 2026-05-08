with members as (
    select * from {{ ref('stg_members') }}
),
loans as (
    select * from {{ ref('stg_loans') }}
),
agg as (
    select
        member_id,
        count(*)                                      as loan_count,
        count(*) filter (where is_open)               as open_loans,
        avg(days_borrowed) filter (where not is_open) as avg_days_borrowed,
        max(loaned_at)                                as last_loaned_at
    from loans
    group by member_id
)
select
    m.member_id,
    m.full_name,
    m.membership_tier,
    m.joined_at,
    coalesce(a.loan_count, 0) as loan_count,
    coalesce(a.open_loans, 0) as open_loans,
    a.avg_days_borrowed,
    a.last_loaned_at
from members m
left join agg a using (member_id)
