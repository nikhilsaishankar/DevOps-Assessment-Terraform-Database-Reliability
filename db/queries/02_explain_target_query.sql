-- EXPLAIN for the target query, with real timings and buffer counts.
--
-- What to look for:
--   * "Index Only Scan using idx_hotel_bookings_city_created_at"
--   * "Heap Fetches: 0"            - the index answered the query by itself
--   * Index Cond containing BOTH the city equality and the created_at range
--
-- If you instead see a "Seq Scan", the usual cause is that the table has not
-- been analysed since it was seeded. Run: ANALYZE hotel_bookings;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT org_id,
       status,
       COUNT(*)    AS bookings,
       SUM(amount) AS total_amount
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
