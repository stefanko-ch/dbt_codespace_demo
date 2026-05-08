select
    member_id,
    full_name,
    joined_at::date as joined_at,
    membership_tier
from {{ ref('raw_members') }}
