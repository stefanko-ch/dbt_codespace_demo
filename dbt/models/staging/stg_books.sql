select
    book_id,
    title,
    author,
    genre,
    published_year
from {{ ref('raw_books') }}
