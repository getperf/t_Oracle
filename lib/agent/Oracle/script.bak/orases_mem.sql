select /*+ ORDERED */
       s.sid,v.LOGON_TIME,n.name,max(s.value) memory,v.MODULE
  from v$session v,v$sesstat s,v$statname n
  where n.statistic# = s.statistic#
  and   n.name in ('session pga memory max')
  and s.sid = v.sid
  group by n.name,s.sid,v.MODULE,v.LOGON_TIME
  order by 1,2,3 desc
;
