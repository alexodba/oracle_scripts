/*
#*****************************************************************************
#  SOURCE          : https://github.com/alexodba/oracle_scripts/
#  VERSION         : $Revision: 1.0 $
#  AUTHOR          : Alexander Sobyanin
#  IDEA            : Yury Velikanov
#                    http://www.pythian.com/blog/case-study-how-to-return-a-good-sql-execution-plan-from-10g-days-after-11g-migration/
#  This script creates 10.2 execution plan baseline for 11g statement
#
#  USAGE: sql10plan.sql sql_id
#
#*****************************************************************************
*/

SET SERVEROUT ON

WHENEVER SQLERROR EXIT;

ACCEPT s_sql_id PROMPT 'SQL_ID (&1): ' DEFAULT &1 HIDE

SET VERIFY OFF
SET PAGES 0 FEED OFF LINES 300 TRIMSP ON

DECLARE
  n_PLAN_HASH_VALUE10     NUMBER;
  n_PLAN_HASH_VALUE11     NUMBER;
  n_tmp                   NUMBER;
  v_sql                   VARCHAR2(32000);
  v_address               RAW(8);
  n_HASH_VALUE            NUMBER;

  v_PARSING_SCHEMA_NAME   VARCHAR2(30);
  C                       NUMBER;
  CURSOR c_last_hash  IS
    SELECT PLAN_HASH_VALUE
      FROM (SELECT p.*, ROWNUM AS rn
              FROM (  SELECT DISTINCT PLAN_HASH_VALUE, child_address, timestamp
                        FROM v$sql_plan
                       WHERE sql_id = '&s_sql_id'
                    ORDER BY timestamp DESC) p)
     WHERE rn = 1;
BEGIN
  --check for existing base-lines
  SELECT COUNT(1)
    INTO n_tmp
    FROM dba_sql_plan_baselines p, v$sqlarea s
   WHERE s.exact_matching_signature = p.signature
     AND s.sql_id = '&s_sql_id';
  --if exists output delete statements and exit
  IF n_tmp != 0 THEN
    FOR i
      IN (SELECT 'DECLARE n NUMBER; BEGIN n := DBMS_SPM.DROP_SQL_PLAN_BASELINE(sql_handle => ''' || SQL_HANDLE || ''', plan_name => ''' || PLAN_NAME || '''); END; 
                      /'
                   AS cmd
            FROM dba_sql_plan_baselines p, v$sqlarea s
           WHERE s.exact_matching_signature = p.signature
             AND s.sql_id = '&s_sql_id') LOOP
      DBMS_OUTPUT.put_line(i.cmd);
    END LOOP;
    raise_application_error(-20001, 'SQL baseline(s) already exists for this query. Drop them first by running above commands');
  END IF;
  DBMS_OUTPUT.put_line('Parsing for:&s_sql_id');

  BEGIN
    --try to load sqltext from v$sqlarea first
    SELECT sql_fulltext
          ,PARSING_SCHEMA_NAME
          ,address
          ,hash_value
      INTO v_sql
          ,v_PARSING_SCHEMA_NAME
          ,v_address
          ,n_hash_value
      FROM V$SQLAREA
     WHERE sql_id = '&s_sql_id';
    -- remove all the statement and children
    sys.DBMS_SHARED_POOL.purge(v_address || ',' || n_hash_value, 'c', 65);

    DBMS_OUTPUT.put_line('Cursor has been purged from the shared pool.');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        --when not found load from AWR
        SELECT t.SQL_TEXT, s.PARSING_SCHEMA_NAME
          INTO v_sql, v_PARSING_SCHEMA_NAME
          FROM DBA_HIST_SQLTEXT t
              ,(  SELECT sql_id, PARSING_SCHEMA_NAME, ROWNUM AS rn
                    FROM DBA_HIST_SQLSTAT
                   WHERE sql_id = '&s_sql_id'
                ORDER BY snap_id DESC) s
         WHERE t.sql_id = '&s_sql_id'
           AND t.sql_id = s.sql_id
           AND s.rn = 1;
        DBMS_OUTPUT.put_line('Found SQL in AWR');
      END;
    WHEN OTHERS THEN
      RAISE;
  END;

  EXECUTE IMMEDIATE 'ALTER SESSION SET current_schema=' || v_PARSING_SCHEMA_NAME;
  EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_features_enable=''10.2.0.5''';
  c := DBMS_SQL.open_cursor;
  DBMS_SQL.parse(c, v_sql, DBMS_SQL.NATIVE);
  DBMS_SQL.close_cursor(c);
  OPEN c_last_hash;
  FETCH c_last_hash INTO n_PLAN_HASH_VALUE10;
  CLOSE c_last_hash;
  DBMS_OUTPUT.put_line('Current plan hash value:' || n_PLAN_HASH_VALUE10);
  EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_features_enable=''11.2.0.3''';
  EXECUTE IMMEDIATE 'ALTER SESSION SET optimizer_features_enable=''11.2.0.3''';
  c := DBMS_SQL.open_cursor;
  DBMS_SQL.parse(c, v_sql, DBMS_SQL.NATIVE);
  DBMS_SQL.close_cursor(c);
  OPEN c_last_hash;
  FETCH c_last_hash INTO n_PLAN_HASH_VALUE11;
  CLOSE c_last_hash;
  DBMS_OUTPUT.put_line('New plan hash value:' || n_PLAN_HASH_VALUE11);
  IF n_PLAN_HASH_VALUE10 = n_PLAN_HASH_VALUE11 THEN
    raise_application_error(-20001, '11.2 and 10.2 plans are the same. Nothing to be done.');
  END IF;
  n_tmp :=
    DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(sql_id            => '&s_sql_id'
                                         ,plan_hash_value   => n_PLAN_HASH_VALUE10
                                         ,FIXED             => 'YES'
                                         ,ENABLED           => 'YES');
  IF n_tmp = 0 THEN
    raise_application_error(-20001, 'Plan has not been loaded by DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE');
  END IF;
END;
/


PROMPT New SQL baseline has been created.

SELECT *
  FROM TABLE(DBMS_XPLAN.display_sql_plan_baseline(sql_handle   => (SELECT DISTINCT p.sql_handle
                                                                     FROM dba_sql_plan_baselines P, v$sqlarea s
                                                                    WHERE s.exact_matching_signature = p.signature
                                                                      AND s.sql_id = '&s_sql_id')
                                                 ,format       => 'typical'));
