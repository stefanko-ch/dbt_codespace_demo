{{ config(materialized='table') }}

with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2010-01-01' as date)",
        end_date="cast('2031-01-01' as date)"
    ) }}
)

select
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} as date_key,

    date_day                            as date_actual,
    extract(year    from date_day)::int as year,
    extract(quarter from date_day)::int as quarter,
    extract(month   from date_day)::int as month,
    to_char(date_day, 'TMMonth')        as month_name,
    extract(day     from date_day)::int as day_of_month,
    extract(dow     from date_day)::int as day_of_week,
    to_char(date_day, 'TMDay')          as day_name,
    extract(week    from date_day)::int as iso_week,

    (extract(dow from date_day) in (0, 6)) as is_weekend,
    (date_trunc('quarter', date_day) = date_day) as is_quarter_start,
    (date_day = (date_trunc('month', date_day) + interval '1 month' - interval '1 day')::date) as is_month_end
from spine
