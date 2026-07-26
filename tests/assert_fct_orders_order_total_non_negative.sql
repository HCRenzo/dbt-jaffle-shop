-- Falla si existe alguna orden con order_total negativo: no tiene sentido
-- de negocio y ningún test genérico (unique/not_null/accepted_values/
-- relationships) puede expresar esta regla.
select
    order_id,
    order_total
from {{ ref('fct_orders') }}
where order_total < 0
