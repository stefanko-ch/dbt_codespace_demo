with source as (
    select * from {{ source('adventureworks', 'sales_order_header') }}
)
select
    sales_order_id,
    customer_id,
    sales_person_id,
    territory_id,

    order_date::date as order_date,
    due_date::date   as due_date,
    ship_date::date  as ship_date,

    online_order_flag as is_online,
    sales_order_number,
    purchase_order_number,
    account_number,

    sub_total as subtotal_amount,
    tax_amt   as tax_amount,
    freight   as freight_amount,
    total_due as total_amount,

    (sub_total + tax_amt + freight) as computed_total,

    status,
    case status
        when 1 then 'in process'
        when 2 then 'approved'
        when 3 then 'backordered'
        when 4 then 'rejected'
        when 5 then 'shipped'
        when 6 then 'cancelled'
        else 'unknown'
    end as status_name,

    modified_date as source_modified_at
from source
