{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='fail',
    )
}}

with orders_payments as (

    select * from {{ ref('int_orders_payments_joined') }}

    {% if is_incremental() %}
    where order_date > (select max(order_date) from {{ this }})
    {% endif %}

),

final as (

    select
        order_id,
        customer_id,
        order_date,
        order_status,
        amount as order_total

    from orders_payments

)

select * from final
