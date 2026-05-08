with source as (
    select * from {{ source('adventureworks', 'sales_territory') }}
)
select
    territory_id,
    name as territory_name,
    country_region_code,
    group_name as region_group,
    sales_ytd,
    sales_last_year,
    cost_ytd,
    cost_last_year,
    modified_date as source_modified_at
from source
