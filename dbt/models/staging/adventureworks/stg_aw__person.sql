with source as (
    select * from {{ source('adventureworks', 'person') }}
)

select
    business_entity_id as person_id,
    person_type,
    title,
    first_name,
    middle_name,
    last_name,
    suffix,

    trim(
        concat_ws(' ',
            nullif(trim(first_name),  ''),
            nullif(trim(middle_name), ''),
            nullif(trim(last_name),   '')
        )
    ) as full_name,

    email_promotion,
    modified_date as source_modified_at
from source
