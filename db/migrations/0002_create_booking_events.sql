-- 0002_create_booking_events.sql
-- Append-only event log for each booking.
--
-- booking_id carries a real foreign key to hotel_bookings. The brief's sketch
-- leaves it as a bare UUID; without the constraint the log silently accumulates
-- orphan rows after any booking deletion, which then show up as impossible
-- numbers in event-based reporting. ON DELETE CASCADE keeps the two in step.

BEGIN;

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL    PRIMARY KEY,
    booking_id UUID         NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT booking_events_booking_fk
        FOREIGN KEY (booking_id)
        REFERENCES hotel_bookings (id)
        ON DELETE CASCADE
);

COMMENT ON TABLE  booking_events            IS 'Append-only audit trail of booking state changes.';
COMMENT ON COLUMN booking_events.event_type IS 'booking_created, payment_authorized, booking_confirmed, booking_cancelled, refund_issued.';
COMMENT ON COLUMN booking_events.payload    IS 'Event specific detail. JSONB so it can be queried and indexed, not just stored.';

COMMIT;
