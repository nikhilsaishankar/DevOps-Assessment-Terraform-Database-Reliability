-- Shape of the seeded data: enough to confirm the brief's requirements
-- (100+ bookings, multiple cities, organisations, statuses, and events) in
-- one round trip.

\echo '--- totals ---'
SELECT
    (SELECT COUNT(*) FROM hotel_bookings)                     AS bookings,
    (SELECT COUNT(*) FROM booking_events)                     AS events,
    (SELECT COUNT(DISTINCT booking_id) FROM booking_events)   AS bookings_with_events,
    (SELECT COUNT(DISTINCT org_id) FROM hotel_bookings)       AS organisations,
    (SELECT COUNT(DISTINCT city) FROM hotel_bookings)         AS cities,
    (SELECT COUNT(DISTINCT status) FROM hotel_bookings)       AS statuses;

\echo '--- bookings per city, and how many fall in the query window ---'
SELECT
    city,
    COUNT(*)                                                                       AS total,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')               AS last_30_days,
    ROUND(SUM(amount), 2)                                                          AS total_amount
FROM hotel_bookings
GROUP BY city
ORDER BY total DESC;

\echo '--- bookings per status ---'
SELECT status, COUNT(*) AS total, ROUND(SUM(amount), 2) AS total_amount
FROM hotel_bookings
GROUP BY status
ORDER BY total DESC;

\echo '--- events per type ---'
SELECT event_type, COUNT(*) AS total
FROM booking_events
GROUP BY event_type
ORDER BY total DESC;

\echo '--- created_at span ---'
SELECT MIN(created_at) AS oldest, MAX(created_at) AS newest FROM hotel_bookings;
