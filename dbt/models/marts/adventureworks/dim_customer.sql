with customers as (
    select * from {{ ref('stg_aw__customer') }}
),
people as (
    select * from {{ ref('stg_aw__person') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['c.customer_id']) }} as customer_key,

    c.customer_id,
    c.customer_type,
    p.full_name as customer_name,
    p.first_name,
    p.last_name,
    p.email_promotion,
    c.territory_id,
    c.store_id
from customers c
left join people p on p.person_id = c.person_id
