with source as (
    select * from {{ source('adventureworks', 'sales_order_detail') }}
)
select
    sales_order_id,
    sales_order_detail_id,
    product_id,
    order_qty,
    unit_price,
    unit_price_discount,
    line_total,
    carrier_tracking_number,
    modified_date as source_modified_at
from source
