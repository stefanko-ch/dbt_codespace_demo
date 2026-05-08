with books as (
    select * from {{ ref('stg_books') }}
),
loans as (
    select * from {{ ref('stg_loans') }}
),
agg as (
    select
        book_id,
        count(*)                                       as loan_count,
        count(distinct member_id)                      as unique_borrowers,
        count(*) filter (where is_open)                as open_loans,
        sum(days_borrowed) filter (where not is_open)  as total_days_borrowed,
        avg(days_borrowed) filter (where not is_open)  as avg_days_borrowed,
        max(loaned_at)                                 as last_loaned_at
    from loans
    group by book_id
)
select
    b.book_id,
    b.title,
    b.author,
    b.genre,
    b.published_year,
    coalesce(a.loan_count, 0)        as loan_count,
    coalesce(a.unique_borrowers, 0)  as unique_borrowers,
    coalesce(a.open_loans, 0)        as open_loans,
    coalesce(a.total_days_borrowed, 0) as total_days_borrowed,
    a.avg_days_borrowed,
    a.last_loaned_at
from books b
left join agg a using (book_id)
