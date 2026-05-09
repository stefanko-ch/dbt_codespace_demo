{#
  Override dbt's default schema-naming behaviour for Postgres.

  Default behaviour concatenates `<target.schema>_<custom_schema>`, which
  turns `+schema: marts` into `public_marts`. For a single-tenant workshop
  warehouse that's just noise -- we want plain `marts` and `staging`.

  This macro:
    - Uses the model's `+schema:` value verbatim when set (no prefix).
    - Falls back to `target.schema` when no `+schema:` is configured.

  Trade-off: in a multi-tenant or shared dbt deployment, the prefix exists
  precisely to namespace per-developer schemas. We're a single-target
  workshop project, so we can drop it safely.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
