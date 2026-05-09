with source as (
    select * from {{ source('adventureworks', 'product') }}
)
select
    product_id,
    name as product_name,
    product_number,
    color,
    standard_cost,
    list_price,
    size,
    weight,
    product_line,
    class as product_class,
    style as product_style,
    product_subcategory_id,
    sell_start_date,
    sell_end_date,
    discontinued_date,

    (sell_end_date is null and discontinued_date is null) as is_active,

    modified_date as source_modified_at
from source
