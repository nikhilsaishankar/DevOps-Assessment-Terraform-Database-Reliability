-- 0003_indexes.sql
-- Indexes, with the reasoning for each.
--
-- ===========================================================================
-- The query being optimised (Part 5 of the brief)
-- ===========================================================================
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi'
--     AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- Three things the planner has to do: find the matching rows, read four
-- columns from each of them, then aggregate. The index below addresses all
-- three.
--
-- Column order: city first because it is an EQUALITY predicate, created_at
-- second because it is a RANGE predicate. A B-tree can only use one range
-- column, and only after every equality column has been pinned down. With
-- (city, created_at) the scan descends straight to city = 'delhi' and then
-- walks a single contiguous run of entries for the last 30 days. Reversing
-- them to (created_at, city) would force a scan of every city's rows inside
-- the time window, discarding most of them.
--
-- INCLUDE (org_id, status, amount): these three are never used to locate rows,
-- only to produce the result. Carrying them as non-key payload makes the index
-- covering, so the aggregate can be answered by an INDEX ONLY SCAN with zero
-- heap fetches. Keeping them out of the key keeps the B-tree key small, which
-- means a shallower tree and more entries per page than if they were key
-- columns.
--
-- DESC on created_at is not required for a >= predicate - a B-tree is
-- scannable in both directions - but it matches the "most recent first" order
-- the rest of the application reads bookings in, so an ORDER BY created_at
-- DESC LIMIT n on the same prefix is also served without a sort.
--
-- Alternatives considered and rejected:
--
--   two single-column indexes on (city) and (created_at)
--       The planner would BitmapAnd them, then visit the heap for every
--       surviving row to read org_id, status and amount. Strictly more I/O,
--       and no index-only scan is possible.
--
--   (city, created_at) with org_id/status as trailing KEY columns
--       No gain. They sit after a range column, so the index cannot deliver
--       rows pre-sorted by (org_id, status) anyway, and the GROUP BY still
--       needs its own hash or sort step. The only effect is a wider key.
--
--   partial index ... WHERE city = 'delhi'
--       Smaller and marginally faster, but it serves exactly one city. The
--       dashboard this query comes from is per-city, so it would need one
--       index per city and would stop helping the moment a new city is added.
--       Worth doing only for a genuinely hot, fixed partition of the data.
--
--   BRIN on created_at
--       Excellent for an append-only table in the hundreds of millions of
--       rows, and far smaller than a B-tree. But it gives no help at all with
--       the city equality, and at this table size the B-tree wins outright.
--
-- Expected plan shape after this index exists and the table has been analysed:
--
--   HashAggregate
--     -> Index Only Scan using idx_hotel_bookings_city_created_at
--          Index Cond: ((city = 'delhi') AND (created_at >= ...))
--          Heap Fetches: 0
--
-- Verify with:  ./scripts/explain.sh
-- ===========================================================================

BEGIN;

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);

COMMENT ON INDEX idx_hotel_bookings_city_created_at IS
    'Covering index for the per-city, trailing-window booking aggregate. Equality column first, range column second, aggregate columns as INCLUDE payload so the query is answered by an index-only scan.';

-- Tenant-scoped reads. Almost every other query in a multi-tenant booking
-- system starts with "for this organisation, recently", and that access path
-- shares nothing with the city index above.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_org_created_at
    ON hotel_bookings (org_id, created_at DESC);

COMMENT ON INDEX idx_hotel_bookings_org_created_at IS
    'Tenant timeline: org_id equality then created_at range/ordering.';

-- PostgreSQL does not index the referencing side of a foreign key
-- automatically. Without this, every DELETE on hotel_bookings has to
-- sequentially scan booking_events to enforce ON DELETE CASCADE, and the
-- natural "show me this booking's history" query is a full scan too.
CREATE INDEX IF NOT EXISTS idx_booking_events_booking_created_at
    ON booking_events (booking_id, created_at DESC);

COMMENT ON INDEX idx_booking_events_booking_created_at IS
    'Supports the ON DELETE CASCADE from hotel_bookings and per-booking event timelines.';

-- Event-type reporting over a time window ("how many cancellations this
-- week"), which otherwise scans the whole log.
CREATE INDEX IF NOT EXISTS idx_booking_events_type_created_at
    ON booking_events (event_type, created_at DESC);

COMMENT ON INDEX idx_booking_events_type_created_at IS
    'Event-type counts over a trailing window.';

COMMIT;

-- Deliberately NOT created here:
--
--   GIN index on booking_events.payload
--       JSONB containment queries (payload @> '{"channel":"ios"}') need one,
--       and it is the right tool when they exist. No query in this repo
--       touches payload in a WHERE clause, and a GIN index is expensive to
--       maintain on an append-heavy table, so adding it now would cost write
--       throughput for no read benefit. The statement, for when that changes:
--
--         CREATE INDEX idx_booking_events_payload_gin
--             ON booking_events USING GIN (payload jsonb_path_ops);
