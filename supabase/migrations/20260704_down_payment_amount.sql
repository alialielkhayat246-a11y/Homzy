-- One-off: fold the actual EGP down-payment amount (price × down_payment%) into
-- the down_payment and payment_plan of already-enriched units (the ones the
-- enrich_catalog RPC set to a bare "5%"). Idempotent: only touches rows whose
-- down_payment is still a bare percentage.
with calc as (
  select id,
         replace(down_payment,'%','')::numeric as pct,
         round(price_from * replace(down_payment,'%','')::numeric / 100) as amount,
         down_payment as dp
  from unit_types
  where down_payment ~ '^[0-9.]+%$'
    and price_from is not null and price_from > 0
)
update unit_types u
set down_payment = u.down_payment || ' (≈ ' || to_char(c.amount,'FM999,999,999') || ' EGP)',
    payment_plan = replace(
        u.payment_plan,
        c.dp || ' down payment',
        c.dp || ' down payment (≈ ' || to_char(c.amount,'FM999,999,999') || ' EGP)')
from calc c
where u.id = c.id;
