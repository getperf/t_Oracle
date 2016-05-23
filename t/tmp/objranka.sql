select
  to_char(d.END_INTERVAL_TIME,'YYYY/MM/DD HH24:MI:SS') TIME,
  b.OWNER,
  DECODE(b.SUBOBJECT_NAME,NULL,b.OBJECT_NAME,b.OBJECT_NAME||'('||b.SUBOBJECT_NAME||')') segment_name,
  c.bytes,
  c.BUFFER_POOL,
  b.OBJECT_TYPE,
  b.TABLESPACE_NAME,
  a.LOGICAL_READS,
  a.LR_ratio,
  a.PHYSICAL_READS,
  a.PR_ratio,
  a.PHYSICAL_WRITES,
  a.RW_ratio
from
  (  select
       a.SNAP_ID,
       a.TS#,
       a.OBJ#,
       a.DATAOBJ#,
       a.LOGICAL_READS_DELTA LOGICAL_READS,
       round((ratio_to_report(a.LOGICAL_READS_DELTA) over ())*100,2) LR_ratio,
       a.PHYSICAL_READS_DELTA PHYSICAL_READS,
       round((ratio_to_report(a.PHYSICAL_READS_DELTA) over ())*100,2) PR_ratio,
       a.PHYSICAL_WRITES_DELTA PHYSICAL_WRITES,
       round((ratio_to_report(a.PHYSICAL_WRITES_DELTA) over ())*100,2) RW_ratio
     from DBA_HIST_SEG_STAT a
     where SNAP_ID = (
       select
         max(SNAP_ID)
       from DBA_HIST_SNAPSHOT)) a,
  DBA_HIST_SEG_STAT_OBJ b,
  dba_segments c,
  DBA_HIST_SNAPSHOT d
where a.TS# = b.TS#
  and a.OBJ# = b.OBJ#
  and a.DATAOBJ# = b.DATAOBJ#
  and b.OWNER <> 'SYS'
  and b.object_name = c.segment_name
  and b.owner = c.owner
  and b.object_type = c.segment_type
  and a.SNAP_ID = d.SNAP_ID
  and nvl(b.SUBOBJECT_NAME,' ') = nvl(c.PARTITION_NAME,' ')
order by PR_ratio desc
