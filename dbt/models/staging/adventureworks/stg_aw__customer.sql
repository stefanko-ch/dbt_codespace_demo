with source as (
    select * from {{ source('adventureworks', 'customer') }}
),

renamed as (
    select
        customer_id,
        person_id,
        store_id,
        territory_id,

        case
            when person_id is not null then 'individual'
            when store_id  is not null then 'store'
            else 'unknown'
        end as customer_type,

        modified_date as source_modified_at
    from source
)

select * from renamed
