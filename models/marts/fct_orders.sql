{{
    config(
        materialized='incremental',
        unique_key='order_id',
        incremental_strategy='merge',
        on_schema_change='fail',
    )
}}

with orders_payments as (

    select opj.* from {{ ref('int_orders_payments_joined') }} as opj

    {% if is_incremental() %}
        where opj.order_date > (select max(prev.order_date) from {{ this }} as prev)
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
