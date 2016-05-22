select
decode(substr(UPPER(s.MACHINE),1,5),
'Y3IDB','Y3DB','Y4IDB','Y4DB','Y5IDB','Y5DB','YIDB0','Y3DB',
'Y3IWE','Y3WEB','Y4IWE','Y4WEB','Y5IWE','Y5WEB',
'YIWFM','Y3WFM','Y4IWF','Y4WFM','Y5IWF','Y5WFM',
'YYYIS','YYYIS',decode(substr(UPPER(s.MACHINE),1,2),'YQ','YQXXX','YI','YIXXX','MISC'))
 MACHINE,
count(s.SID) "SESSION COUNT",count(t.ADDR) "TRUNSACTION_COUNT",
count(decode(s.status,'ACTIVE',1)) "ACTIVES SESSION"
from v$transaction t,v$session s
where t.SES_ADDR(+)=s.SADDR
group by
decode(substr(UPPER(s.MACHINE),1,5),
'Y3IDB','Y3DB','Y4IDB','Y4DB','Y5IDB','Y5DB','YIDB0','Y3DB',
'Y3IWE','Y3WEB','Y4IWE','Y4WEB','Y5IWE','Y5WEB',
'YIWFM','Y3WFM','Y4IWF','Y4WFM','Y5IWF','Y5WFM',
'YYYIS','YYYIS',decode(substr(UPPER(s.MACHINE),1,2),'YQ','YQXXX','YI','YIXXX','MISC'))
