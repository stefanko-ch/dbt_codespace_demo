{{ config(materialized='table') }}

with detail as (
    select * from {{ ref('stg_aw__sales_order_detail') }}
),
header as (
    select * from {{ ref('stg_aw__sales_order_header') }}
),

joined as (
    select
        d.sales_order_id,
        d.sales_order_detail_id,
        h.order_date,
        h.customer_id,
        h.sales_person_id,
        h.territory_id,
        d.product_id,

        d.order_qty,
        d.unit_price,
        d.unit_price_discount,
        d.line_total,

        h.is_online,
        h.status_name as order_status,
        h.sales_order_number
    from detail d
    inner join header h using (sales_order_id)
)

select
    {{ dbt_utils.generate_surrogate_key(['j.order_date']) }}      as date_key,
    {{ dbt_utils.generate_surrogate_key(['j.customer_id']) }}     as customer_key,
    {{ dbt_utils.generate_surrogate_key(['j.product_id']) }}      as product_key,
    {{ dbt_utils.generate_surrogate_key(['j.territory_id']) }}    as territory_key,
    {{ dbt_utils.generate_surrogate_key(['j.sales_person_id']) }} as sales_person_key,

    j.sales_order_id,
    j.sales_order_detail_id,
    j.sales_order_number,
    j.order_status,
    j.is_online,

    j.order_qty,
    j.unit_price,
    j.unit_price_discount,
    j.line_total,

    j.unit_price * j.order_qty                          as gross_amount,
    j.unit_price * j.order_qty * j.unit_price_discount  as discount_amount,
    j.line_total                                        as net_amount

from joined j
