{% snapshot orders_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='order_id',
        strategy='check',
        check_cols=['order_status'],
    )
}}

    select
        id as order_id,
        user_id as customer_id,
        order_date,
        status as order_status
    from {{ ref('raw_orders') }}

{% endsnapshot %}
