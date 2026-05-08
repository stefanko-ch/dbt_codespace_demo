-- Sum of fact_sales.net_amount per order should match the
-- header subtotal_amount within rounding tolerance.

with fact_per_order as (
    select sales_order_id, sum(net_amount) as fact_subtotal
    from {{ ref('fact_sales') }}
    group by sales_order_id
),
header as (
    select sales_order_id, subtotal_amount
    from {{ ref('stg_aw__sales_order_header') }}
)
select
    h.sales_order_id,
    h.subtotal_amount,
    f.fact_subtotal,
    abs(h.subtotal_amount - f.fact_subtotal) as diff
from header h
join fact_per_order f using (sales_order_id)
where abs(h.subtotal_amount - f.fact_subtotal) > 0.01
