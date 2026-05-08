with customers as (
    select * from {{ ref('stg_customers') }}
),
orders as (
    select * from {{ ref('stg_orders') }}
),
agg as (
    select
        customer_id,
        count(*)        as order_count,
        sum(amount)     as total_amount,
        min(order_date) as first_order_at,
        max(order_date) as last_order_at
    from orders
    group by customer_id
)
select
    c.customer_id,
    c.first_name,
    c.last_name,
    coalesce(a.order_count, 0)  as order_count,
    coalesce(a.total_amount, 0) as total_amount,
    a.first_order_at,
    a.last_order_at
from customers c
left join agg a using (customer_id)
