select /*+ ORDERED USE_NL(a s) USE_HASH(n) */
 to_char(sysdate,'YYYY/MM/DD HH24:MI:SS') "TIME",a.SID,n.STATISTIC#,n.name,
decode(n.CLASS,1,'user',2,'redo',4,'enqueue',8,'cache',16,'OS',64,'SQL',n.CLASS) "CLASS", s.value
 from (select sid from
(select sid,nvl(sql_id,PREV_SQL_ID) SQL_ID,osuser from v$session
where MACHINE like 'y3im05hub02%'
and OSUSER = 'starstate') a,STAR_Q1_TBL b
where a.SQL_ID = b.SQL_ID
and b.sql_id ='9w2dxcdw1ypf5') a,v$sesstat s, v$statname n
where s.statistic# = n.statistic#
  and a.SID = s.sid
  and s.value <> 0
  and CLASS not in (32,128)
order by 1,2,s.statistic#
