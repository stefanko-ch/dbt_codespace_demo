with source as (
    select * from {{ source('adventureworks', 'product_subcategory') }}
)
select
    product_subcategory_id,
    product_category_id,
    name as subcategory_name,
    modified_date as source_modified_at
from source
