--
-- "Package": pg_quick_funcs
--

-- LAWS:
--   * All the fuckin' functions should start with "qf_", that's the prefix, don't mess it up!
--   * Any time you add a function here, add its DROP sentence in the uninstall_pg_quick_funcs.sql 
--     or to the qf_uninstall_qf().
--   * Keep decent names. Not those you choose for you kids.
--   * Keep sql and plsql languages. 
--   * Keep the definition with the funciton name in the middle.
--   * functions should have a nice output being executed in the way: select function(); . I know this
--     somehow fishy, but the idea is to make a nice framework.


--
-- Function: qf_help
--
CREATE OR REPLACE FUNCTION qf_help() RETURNS NULL $qf_help$
BEGIN
    RAISE NOTICE ' Help(): ';
    RAISE NOTICE '    qf_help()                 -> This function, idiot.';
END;
$qf_help$ LANGUAGE plpgsql;


--
-- Function: _qf_vw_dbsinfo
--
-- The idea is to return something pretty, not a shity ouput
--

CREATE VIEW _qf_vw_dbsinfo AS
select psd.*, pg_size_pretty(pg_database_size(datname)) as size 
from pg_database pd join pg_stat_database psd using (datname)
order by pg_database_size(datname) desc;

CREATE OR REPLACE FUNCTION qf_dbs_info() RETURNS _qf_vw_dbsinfo AS 
$$ select * from _qf_vw_dbsinfo $$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION qf_dbs_info() RETURNS TABLE
(  
 datid oid,
  datname  name, 
 numbackends    integer                  , 
 xact_commit    bigint                   , 
 xact_rollback  bigint                   , 
 blks_read      bigint                   , 
 blks_hit       bigint                   , 
 tup_returned   bigint                   , 
 tup_fetched    bigint                   , 
 tup_inserted   bigint                   , 
 tup_updated    bigint                   , 
 tup_deleted    bigint                   , 
 conflicts      bigint                   , 
 stats_reset    timestamp with time zone ,  
 size           text
) AS $gf_dbs_info$
select psd.*, pg_size_pretty(pg_database_size(datname)) as size 
from pg_database pd join pg_stat_database psd using (datname)
order by pg_database_size(datname) desc
$gf_dbs_info$
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION qf_dbs_info () RETURNS text AS $qf_dbs_info$
DECLARE
       r record;
       output_text text := '';
BEGIN
       FOR r IN select psd.*, 
                  pg_size_pretty(pg_database_size(datname)) as size 
                from pg_database pd join pg_stat_database psd using (datname)
                order by pg_database_size(datname) desc
       LOOP
              output_text = output_text || 
                 $$========================================== 
                 $$ || 'Database: ' || (r.*).datname || ' (id):' || (r.*).datid || $$
                 $$ || 'Current Backends ' || (r.*).numbackends || $$ 
                 $$ || (r.*)::text || $$
                 $$;
       END LOOP;
       RETURN output_text;
END;
$qf_dbs_info$ LANGUAGE plpgsql;


