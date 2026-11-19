-- Every index on the two tables, with its on-disk size and how often the
-- planner has actually chosen it.
--
-- idx_scan is the column that matters when deciding whether an index is
-- earning its write-time cost: an index with zero scans after a representative
-- workload is pure overhead and should be dropped.

SELECT
    i.relname                                   AS index_name,
    t.relname                                   AS table_name,
    pg_size_pretty(pg_relation_size(i.oid))     AS index_size,
    s.idx_scan                                  AS times_used,
    s.idx_tup_read                              AS tuples_read,
    s.idx_tup_fetch                             AS tuples_fetched,
    pg_get_indexdef(i.oid)                      AS definition
FROM pg_class i
JOIN pg_index ix          ON ix.indexrelid = i.oid
JOIN pg_class t           ON t.oid = ix.indrelid
LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = i.oid
WHERE t.relname IN ('hotel_bookings', 'booking_events')
ORDER BY t.relname, i.relname;
