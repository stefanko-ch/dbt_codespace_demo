with t as (
    select * from {{ ref('stg_aw__sales_territory') }}
)
select
    {{ dbt_utils.generate_surrogate_key(['territory_id']) }} as territory_key,
    territory_id,
    territory_name,
    country_region_code,
    region_group
from t
