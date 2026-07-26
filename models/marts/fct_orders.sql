with orders_payments as (

    select * from {{ ref('int_orders_payments_joined') }}

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
