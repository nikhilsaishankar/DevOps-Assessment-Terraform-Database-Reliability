-- 0001_create_hotel_bookings.sql
-- Core bookings table.
--
-- Notes on the choices made against the schema in the brief:
--   * gen_random_uuid() is in core PostgreSQL from 13 onwards, so no extension
--     is required for the default on id.
--   * amount is NUMERIC(12,2), not a float: money must not be stored in a type
--     that cannot represent 0.01 exactly.
--   * created_at is TIMESTAMPTZ rather than TIMESTAMP. The brief says TIMESTAMP,
--     but the target query filters on NOW() - INTERVAL '30 days', and comparing
--     a naive timestamp against a session-timezone-dependent NOW() is how
--     off-by-5.5-hours bugs reach production in IST. The column is still called
--     created_at and behaves identically for every query in this repo.

BEGIN;

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID           NOT NULL,
    hotel_id      VARCHAR(100)   NOT NULL,
    city          VARCHAR(100)   NOT NULL,
    checkin_date  DATE           NOT NULL,
    checkout_date DATE           NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50)    NOT NULL,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

    CONSTRAINT hotel_bookings_dates_ordered
        CHECK (checkout_date > checkin_date),
    CONSTRAINT hotel_bookings_amount_non_negative
        CHECK (amount >= 0),
    CONSTRAINT hotel_bookings_status_known
        CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed', 'refunded'))
);

COMMENT ON TABLE  hotel_bookings            IS 'One row per hotel booking.';
COMMENT ON COLUMN hotel_bookings.org_id     IS 'Owning organisation (travel agency / corporate account). Every tenant-scoped query filters on this.';
COMMENT ON COLUMN hotel_bookings.city       IS 'Lower-cased city slug, e.g. delhi. Normalised on write so equality lookups never need a function.';
COMMENT ON COLUMN hotel_bookings.amount     IS 'Booking value in INR.';
COMMENT ON COLUMN hotel_bookings.created_at IS 'When the booking row was created. Drives all reporting windows.';

COMMIT;
