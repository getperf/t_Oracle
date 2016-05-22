SELECT /*+ INDEX (s) INDEX(p) */
     s.SID,
     p.SPID,
     s.USERNAME,
     s.MACHINE,
     s.PROGRAM
FROM V$SESSION s, V$PROCESS p
WHERE p.addr = s.paddr
;
