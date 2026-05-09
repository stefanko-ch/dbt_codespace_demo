with sp as (
    select * from {{ ref('stg_aw__sales_person') }}
),
p as (
    select * from {{ ref('stg_aw__person') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['sp.sales_person_id']) }} as sales_person_key,

    sp.sales_person_id,
    p.full_name as sales_person_name,
    sp.territory_id,
    sp.sales_quota,
    sp.commission_pct,
    sp.sales_ytd,
    sp.sales_last_year
from sp
left join p on p.person_id = sp.sales_person_id
