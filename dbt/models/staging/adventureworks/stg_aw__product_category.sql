with source as (
    select * from {{ source('adventureworks', 'product_category') }}
)
select
    product_category_id,
    name as category_name,
    modified_date as source_modified_at
from source
