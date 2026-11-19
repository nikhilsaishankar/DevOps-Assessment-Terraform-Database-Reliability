-- 0100_seed.sql
-- Deterministic seed data. 800 bookings (the brief asks for at least 100),
-- spread over 5 organisations, 8 distinct cities and all 5 booking statuses,
-- plus an event trail for roughly half of them.
--
-- The cities array below has 10 slots but only 8 distinct values: 'delhi'
-- occupies three of them, which is how it ends up as 30% of the rows without
-- needing a random number generator.
--
-- Everything is derived arithmetically from generate_series instead of random()
-- so that two people running `docker compose up` get byte-identical data. That
-- matters here for two reasons: the EXPLAIN output in the README is reproducible,
-- and the row counts that scripts/verify-restore.sh compares are stable.
--
-- Each attribute is derived from a different function of g so that the columns
-- are independent of each other. Deriving city from `g % 10` and both org_id
-- and status from `g % 5` looks fine in isolation, but 10 and 5 share a factor:
-- fixing city = 'delhi' then pins g mod 5, which pins org_id AND status. The
-- first version of this seed did exactly that and the target query returned
-- only 3 of the 25 possible (org_id, status) groups. city now keys off g mod 10
-- while org_id and status key off integer division by two different primes,
-- which leaves them free to vary within any single city.
--
-- Shape of the data, by design:
--   * delhi is 30% of rows, so the target query in 0003_indexes.sql aggregates a
--     meaningful population rather than three rows.
--   * created_at spans the last 73 days, so roughly 40% of each city's rows fall
--     inside the query's 30-day window and the range predicate actually
--     discriminates. A seed where every row was recent would make any index
--     look good.

BEGIN;

WITH params AS (
    SELECT
        ARRAY[
            'a0000000-0000-4000-8000-000000000001',
            'a0000000-0000-4000-8000-000000000002',
            'a0000000-0000-4000-8000-000000000003',
            'a0000000-0000-4000-8000-000000000004',
            'a0000000-0000-4000-8000-000000000005'
        ]::uuid[] AS orgs,
        -- delhi listed three times out of ten: a weighted distribution without
        -- needing a random number generator.
        ARRAY[
            'delhi', 'delhi', 'delhi',
            'mumbai', 'bengaluru', 'hyderabad',
            'pune', 'jaipur', 'goa', 'kolkata'
        ]::text[] AS cities,
        ARRAY[
            'pending', 'confirmed', 'cancelled', 'completed', 'refunded'
        ]::text[] AS statuses
),
generated AS (
    SELECT
        g,
        NOW()
            - (((g * 13) % 73) * INTERVAL '1 day')
            - (((g * 17) % 24) * INTERVAL '1 hour')
            AS created_at,
        1 + ((g * 5) % 6)  AS nights,
        2 + ((g * 19) % 21) AS lead_days,
        -- Integer division, so these do not collapse onto g mod 5 the way
        -- city (g mod 10) does.
        ((g / 7) % 5)  AS org_slot,
        ((g / 13) % 5) AS status_slot
    FROM generate_series(1, 800) AS g
)
INSERT INTO hotel_bookings (
    org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at
)
SELECT
    p.orgs[1 + n.org_slot],
    'HTL-' || to_char(1 + ((n.g * 23) % 40), 'FM0000'),
    p.cities[1 + ((n.g * 3) % 10)],
    (n.created_at + (n.lead_days * INTERVAL '1 day'))::date,
    (n.created_at + ((n.lead_days + n.nights) * INTERVAL '1 day'))::date,
    ROUND((1800 + ((n.g * 977) % 48000))::numeric, 2),
    p.statuses[1 + n.status_slot],
    n.created_at
FROM generated n
CROSS JOIN params p;

-- Event trail for every second booking: 1 to 3 lifecycle events each.
WITH ranked AS (
    SELECT
        id,
        amount,
        created_at,
        ROW_NUMBER() OVER (ORDER BY created_at, id) AS rn
    FROM hotel_bookings
)
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    r.id,
    e.event_type,
    jsonb_build_object(
        'source', 'seed',
        'sequence', e.ord,
        'channel', (ARRAY['web', 'ios', 'android', 'partner_api'])[1 + ((r.rn * 3) % 4)],
        'amount', r.amount
    ),
    r.created_at + (e.ord * INTERVAL '37 minutes')
FROM ranked r
JOIN (
    VALUES
        (1, 'booking_created'),
        (2, 'payment_authorized'),
        (3, 'booking_confirmed')
) AS e(ord, event_type)
    ON e.ord <= 1 + (r.rn % 3)
WHERE r.rn % 2 = 0;

-- Terminal event for bookings that did not complete, so the event log is
-- consistent with the booking status rather than contradicting it.
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    b.id,
    CASE b.status
        WHEN 'refunded' THEN 'refund_issued'
        ELSE 'booking_cancelled'
    END,
    jsonb_build_object(
        'source', 'seed',
        -- last character of hotel_id varies across rows, so this picks a
        -- deterministic but non-constant reason.
        'reason', (ARRAY['guest_request', 'payment_failed', 'hotel_overbooked'])[1 + (ascii(right(b.hotel_id, 1)) % 3)],
        'amount', b.amount
    ),
    b.created_at + INTERVAL '2 hours'
FROM hotel_bookings b
WHERE b.status IN ('cancelled', 'refunded');

COMMIT;

-- VACUUM (not just ANALYZE) on purpose, and outside the transaction because
-- VACUUM cannot run inside one. ANALYZE alone refreshes the planner statistics,
-- but an INDEX ONLY SCAN still has to visit the heap for any page the
-- visibility map does not mark all-visible. Without this, the plan in the
-- README would report a non-zero "Heap Fetches" immediately after seeding and
-- the covering index would look like it was not working.
VACUUM (ANALYZE) hotel_bookings;
VACUUM (ANALYZE) booking_events;

-- Report what was actually created, so `docker compose logs db` is enough to
-- confirm the seed succeeded.
DO $$
DECLARE
    v_bookings        bigint;
    v_events          bigint;
    v_orgs            bigint;
    v_cities          bigint;
    v_statuses        bigint;
    v_delhi_30d       bigint;
    v_with_events     bigint;
    v_oldest          timestamptz;
    v_delhi_groups    bigint;
    v_newest          timestamptz;
BEGIN
    SELECT COUNT(*), COUNT(DISTINCT org_id), COUNT(DISTINCT city),
           COUNT(DISTINCT status), MIN(created_at), MAX(created_at)
      INTO v_bookings, v_orgs, v_cities, v_statuses, v_oldest, v_newest
      FROM hotel_bookings;

    SELECT COUNT(*) INTO v_events FROM booking_events;

    SELECT COUNT(DISTINCT booking_id) INTO v_with_events FROM booking_events;

    SELECT COUNT(*) INTO v_delhi_30d
      FROM hotel_bookings
     WHERE city = 'delhi'
       AND created_at >= NOW() - INTERVAL '30 days';

    RAISE NOTICE '--------------------------------------------------';
    RAISE NOTICE 'seed complete';
    RAISE NOTICE '  hotel_bookings          : %', v_bookings;
    RAISE NOTICE '  booking_events          : %', v_events;
    RAISE NOTICE '  bookings with events    : %', v_with_events;
    RAISE NOTICE '  distinct organisations  : %', v_orgs;
    RAISE NOTICE '  distinct cities         : %', v_cities;
    RAISE NOTICE '  distinct statuses       : %', v_statuses;
    RAISE NOTICE '  created_at range        : % .. %', v_oldest, v_newest;
    RAISE NOTICE '  delhi, last 30 days     : %  <- population of the target query', v_delhi_30d;
    RAISE NOTICE '--------------------------------------------------';

    IF v_bookings < 100 THEN
        RAISE EXCEPTION 'seed produced only % bookings, the brief requires at least 100', v_bookings;
    END IF;

    IF v_delhi_30d = 0 THEN
        RAISE EXCEPTION 'seed produced no delhi bookings in the last 30 days; the target query would return an empty set';
    END IF;

    -- The target query groups by (org_id, status). If city, org_id and status
    -- are correlated, that grouping collapses to a handful of rows and the
    -- query stops being a meaningful test of the index. Guard against a future
    -- edit reintroducing the correlation.
    SELECT COUNT(*) INTO v_delhi_groups
      FROM (
        SELECT org_id, status
          FROM hotel_bookings
         WHERE city = 'delhi'
           AND created_at >= NOW() - INTERVAL '30 days'
         GROUP BY org_id, status
      ) g;

    RAISE NOTICE '  delhi 30d (org,status) groups : %  (of 25 possible)', v_delhi_groups;

    IF v_delhi_groups < 10 THEN
        RAISE EXCEPTION 'target query yields only % (org_id, status) groups; city/org/status look correlated', v_delhi_groups;
    END IF;
END
$$;
