select/*+ ORDERED USE_NL(b) NO_MERGE(a) */
 to_char(sysdate,'YYYY/MM/DD HH24:MI:SS') as "DATE",
 b.SQL_ID,
 substr(b.SQL_TEXT, 1, 30),
 b.OLD_HASH_VALUE "HASH_VALUE",
 sum(b.EXECUTIONS) "EXECUTIONS",
 sum(b.DISK_READS) "DISK_READS",
 sum(b.BUFFER_GETS) "BUFFER_GETS",
 sum(b.ROWS_PROCESSED) "ROWS_PROCESSED",
 sum(b.CPU_TIME) "CPU_TIME",
 sum(b.ELAPSED_TIME) "ELAPSED_TIME",
 b.COMMAND_TYPE
from (select /*+ ORDERED USE_NL(a b) NO_MERGE(a) */
distinct b.sql_id
from
(select distinct SESSION_ID from v$active_session_history
where sql_id = 'f2n43grqcb1qn') a,v$active_session_history b
where a.SESSION_ID = b.SESSION_ID) a,v$sql b
where a.sql_id = b.sql_id
group by
 b.SQL_ID,
 b.SQL_TEXT,
 b.OLD_HASH_VALUE,
 b.COMMAND_TYPE
