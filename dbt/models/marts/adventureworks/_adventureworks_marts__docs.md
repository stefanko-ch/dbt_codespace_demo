{% docs fact_sales_grain %}
**Grain:** one row per `(sales_order_id, sales_order_detail_id)`.

Every measure on `fact_sales` is additive at this grain. Header-level
attributes carried along (status, online flag, order number) repeat for
every line on the order -- that's intentional, it lets BI users filter
without joining back to a header table.
{% enddocs %}

{% docs surrogate_key %}
Generated via `dbt_utils.generate_surrogate_key` (an MD5 hash of the
business key). This decouples downstream from the source's natural key
strategy and makes joins trivially indexable.
{% enddocs %}
