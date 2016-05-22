SELECT
    OWNER,
    TABLE_NAME,
    NUM_ROWS,
    AVG_ROW_LEN,
    INITIAL_EXTENT,
    BLOCKS,
    CHAIN_CNT
FROM
    SYS.DBA_TABLES
ORDER BY
    OWNER,
    TABLE_NAME
;