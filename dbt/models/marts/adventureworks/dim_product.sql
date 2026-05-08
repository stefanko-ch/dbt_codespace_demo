with p as (
    select * from {{ ref('stg_aw__product') }}
),
sc as (
    select * from {{ ref('stg_aw__product_subcategory') }}
),
c as (
    select * from {{ ref('stg_aw__product_category') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['p.product_id']) }} as product_key,

    p.product_id,
    p.product_name,
    p.product_number,
    p.color,
    p.size,
    p.weight,
    p.product_line,
    p.product_class,
    p.product_style,
    p.standard_cost,
    p.list_price,

    p.product_subcategory_id,
    sc.subcategory_name,
    sc.product_category_id,
    c.category_name,

    p.sell_start_date,
    p.sell_end_date,
    p.discontinued_date,
    p.is_active

from p
left join sc on sc.product_subcategory_id = p.product_subcategory_id
left join c  on c.product_category_id     = sc.product_category_id
