SELECT 
  STATUS , 
  COUNT ( * ) 
FROM 
  V$LOG 
GROUP BY 
  STATUS
;
