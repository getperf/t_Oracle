SELECT TIME
     , N.OWNER
     , DECODE(N.SUBOBJECT_NAME,NULL,N.OBJECT_NAME,N.OBJECT_NAME||'('||N.SUBOBJECT_NAME||')') OBJECT_NAME
     , N.OBJECT_TYPE
     , X.BUFFER_POOL
     , SUM(X.BYTES)
     , SUM(R.LOGICAL_READS)
     , SUM(R.PHYSICAL_READS)
  FROM STATS$SEG_STAT_OBJ N
     , (SELECT *
          FROM (SELECT TO_CHAR ( I.SNAP_TIME, 'YYYY/MM/DD HH24:MI:SS' ) TIME
                     , E.DATAOBJ#
                     , E.OBJ#
                     , E.DBID
                     , E.LOGICAL_READS - NVL(B.LOGICAL_READS, 0) LOGICAL_READS
                     , E.PHYSICAL_READS - NVL(B.PHYSICAL_READS, 0) PHYSICAL_READS
                  FROM STATS$SEG_STAT E
                     , STATS$SEG_STAT B
                     , STATS$SNAPSHOT I
                 WHERE B.SNAP_ID                                  = &STARTSNAP_ID
                   AND E.SNAP_ID                                  = &ENDSNAP_ID
                   AND I.SNAP_ID                                  = E.SNAP_ID
                   AND B.DBID                                     = E.DBID
                   AND B.INSTANCE_NUMBER                          = E.INSTANCE_NUMBER
                   AND E.OBJ#                                     = B.OBJ#
                   AND E.DATAOBJ#                                 = B.DATAOBJ#
                   AND E.LOGICAL_READS - NVL(B.LOGICAL_READS, 0)  > 0
                 ORDER BY LOGICAL_READS DESC) D
          WHERE ROWNUM <= 101
UNION
        SELECT *
          FROM (SELECT TO_CHAR ( I.SNAP_TIME, 'YYYY/MM/DD HH24:MI:SS' ) TIME
                     , E.DATAOBJ#
                     , E.OBJ#
                     , E.DBID
                     , E.LOGICAL_READS - NVL(B.LOGICAL_READS, 0) LOGICAL_READS
                     , E.PHYSICAL_READS - NVL(B.PHYSICAL_READS, 0) PHYSICAL_READS
                  FROM STATS$SEG_STAT E
                     , STATS$SEG_STAT B
                     , STATS$SNAPSHOT I
                 WHERE B.SNAP_ID                                  = &STARTSNAP_ID
                   AND E.SNAP_ID                                  = &ENDSNAP_ID
                   AND I.SNAP_ID                                  = E.SNAP_ID
                   AND B.DBID                                     = E.DBID
                   AND B.INSTANCE_NUMBER                          = E.INSTANCE_NUMBER
                   AND E.OBJ#                                     = B.OBJ#
                   AND E.DATAOBJ#                                 = B.DATAOBJ#
                   AND E.PHYSICAL_READS - NVL(B.PHYSICAL_READS, 0)  > 0
                 ORDER BY PHYSICAL_READS DESC) D
          WHERE ROWNUM <= 101
) R,DBA_SEGMENTS X
 WHERE N.DATAOBJ# = R.DATAOBJ#
   AND N.OBJ#     = R.OBJ#
   AND N.DBID     = R.DBID
   AND N.OBJECT_NAME = X.SEGMENT_NAME
   AND N.OWNER = X.OWNER
   AND N.OBJECT_TYPE = X.SEGMENT_TYPE
   AND NVL(N.SUBOBJECT_NAME,'0') = NVL(X.PARTITION_NAME,'0')
GROUP BY
     TIME
     , N.OWNER
     , DECODE(N.SUBOBJECT_NAME,NULL,N.OBJECT_NAME,N.OBJECT_NAME||'('||N.SUBOBJECT_NAME||')')
     , N.OBJECT_TYPE
     , X.BUFFER_POOL
;
