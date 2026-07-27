with source as (

    select * from {{ ref('raw_payments') }}

),

renamed as (

    select
        id as payment_id,
        order_id,
        payment_method,
        {{ cents_to_dollars('amount') }} as payment_amount

    from source

)

select * from renamed
