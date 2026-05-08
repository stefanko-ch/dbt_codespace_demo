select
    loan_id,
    book_id,
    member_id,
    loaned_at::date   as loaned_at,
    returned_at::date as returned_at,
    case
        when returned_at is null then null
        else (returned_at::date - loaned_at::date)
    end as days_borrowed,
    returned_at is null as is_open
from {{ ref('raw_loans') }}
