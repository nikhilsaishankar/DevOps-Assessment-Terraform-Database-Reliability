-- The query from Part 5 of the brief, verbatim.
--
--   docker compose exec -T db psql -U hotels_admin -d hotels -f /queries/01_target_query.sql

SELECT org_id,
       status,
       COUNT(*)    AS bookings,
       SUM(amount) AS total_amount
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
