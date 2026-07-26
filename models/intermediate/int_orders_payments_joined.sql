with orders as (

    select * from {{ ref('stg_orders') }}

),

payments as (

    select * from {{ ref('stg_payments') }}

),

order_payments as (

    select
        order_id,
        sum(payment_amount) as total_amount

    from payments
    group by order_id

),

joined as (

    select
        orders.order_id,
        orders.customer_id,
        orders.order_date,
        orders.order_status,
        coalesce(order_payments.total_amount, 0) as amount

    from orders
    left join order_payments
        on orders.order_id = order_payments.order_id

)

select * from joined
