-- Sum of order_detail.line_total per order should match
-- order_header.subtotal_amount within a small rounding tolerance.

with line_totals as (
    select
        sales_order_id,
        sum(line_total) as lines_sum
    from {{ ref('stg_aw__sales_order_detail') }}
    group by sales_order_id
),
header_totals as (
    select
        sales_order_id,
        subtotal_amount
    from {{ ref('stg_aw__sales_order_header') }}
)

select
    h.sales_order_id,
    h.subtotal_amount,
    l.lines_sum,
    abs(h.subtotal_amount - l.lines_sum) as diff
from header_totals h
join line_totals  l using (sales_order_id)
where abs(h.subtotal_amount - l.lines_sum) > 0.01
