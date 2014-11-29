--
-- "Package": pg_quick_funcs
--

-- LAWS:
--   * All the fuckin' functions should start with "qf_", that's the prefix, don't mess it up!
--   * Any time you add a function here, add its DROP sentence in the uninstall_pg_quick_funcs.sql 
--     or to the qf_uninstall_qf().
--   * Keep decent names. Not those you choose for you kids.
--   * Keep sql and plpgsql languages. 
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

--
-- Function: qf_dbs_info
--
-- TODO:
--   Overload this function with "name" parameter to filter down per database basis.
--

CREATE OR REPLACE FUNCTION qf_dbs_info () RETURNS text AS $qf_dbs_info$
DECLARE
       r record;
       output_text text := '';
       sum_write bigint;
       ratio_rw bigint;
       version_num int;
BEGIN
       SELECT setting INTO version_num FROM pg_settings WHERE name = 'server_version_num';
       FOR r IN select psd.*, 
                  pg_size_pretty(pg_database_size(datname)) as size 
                from pg_database pd join pg_stat_database psd using (datname)
                where psd.datname NOT IN ('template0','template1')
                order by pg_database_size(datname) desc
       LOOP
              sum_write = (r.tup_inserted) + (r.tup_updated) + (r.tup_deleted);
              ratio_rw = 0;
              output_text = output_text || 
                 $$
                 ========================================== 
                 $$ || 'Database: ' || (r.datname) || ' (id):' || (r.datid)::text || $$
                 $$ || 'Version Number              ' || (version_num)::text || $$
                 $$ || 'Current Backends            ' || (r.numbackends)::text || $$ 
                 $$ || 'Size :                      ' || (r.size)::text || $$ 
                 $$ || 'Comit/Rollback :            ' || (r.xact_commit)::text || '/' || (r.xact_rollback)::text || $$
                 $$ || 'Blks Read/hit  :            ' || (r.blks_read)::text || '/' || (r.blks_hit)::text || $$
                 $$ || 'Tuples writen :             ' || sum_write || $$
                 $$ || 'R/W Ratio:                  ' || ratio_rw || $$
                 $$ || 'ShBuf Effectiveness (% hit):' || (((r.blks_hit) * 100 + 1) / ((r.blks_read) + (r.blks_hit) + 1) )::text || $$
                 $$; 
                 --|| (r.*)::text || $$
                 -- $$ || 'Conflicts :                 ' || (r.conflicts) || $$
                 --$$;
              CASE 
                 WHEN (version_num > 90100) THEN
                    -- output_text = output_text ||
                    -- temp_files and bytes, deadlocks
                    FOR r IN SELECT * FROM pg_stat_database_conflicts WHERE datname NOT IN ('template0','template1')
                    LOOP
                        output_text = output_text || $$
                        
                        $$ || 'Tablespaces                   :' || (r.confl_tablespace) || $$
                        $$ || 'Lock issues                   :' || (r.confl_lock) || $$
                        $$ || 'Snapshots issues              :' || (r.confl_snapshot) || $$
                        $$ || 'Bufferpin issues              :' || (r.confl_bufferpin) || $$
                        $$ || 'Deadlocks issues              :' || (r.confl_deadlock) || $$
                        $$;
                    END LOOP;
              ELSE 
                NULL;
              END CASE;
       END LOOP;
       RETURN output_text;
END;
$qf_dbs_info$ LANGUAGE plpgsql;

--
-- Function : qf_find_bad_toast
--    Author: Josh Berkus http://www.databasesoup.com/2014/07/improved-toast-corruption-function.html
--
create or replace function qf_find_bad_toast (
   tablename text,
   pk_col text
)
returns text
language plpgsql
as
$qf_find_bad_toast$
declare
   curid BIGINT := 0;
   badid BIGINT;
begin
FOR badid IN EXECUTE 'SELECT ' || pk_col || ' FROM ' || tablename LOOP
   curid = curid + 1;
   if curid % 100000 = 0 then
       raise notice '% rows inspected', curid;
   end if;
   begin
       EXECUTE 'COPY ( SELECT * FROM ' || tablename || ' WHERE ' ||
            pk_col || ' = ' || cast(badid as text) || ') TO ''/tmp/testout'';';
   exception
       when others then
           raise notice 'data for id % is corrupt', badid;
           continue;
   end;
end loop;
return 'done checking all rows';
end;
$qf_find_bad_toast$;



--
-- Function: qf_toastcheck_writer
-- Developed by Alvaro Herrera as shown in http://alvherre.livejournal.com/4404.html
--

create or replace function qf_toastcheck_writer(text) returns void language plpgsql as $qf_toastcheck_writer$
  declare
    func text;
    funcname text;
    column record;
    pkc    record;
    indent text;
    colrec record;
    pkcols text;
    pkformat text;
    pk_col_ary text[];
  begin

  pkcols = '';
  pkformat = '';
  pk_col_ary = '{}';
  funcname = 'toastcheck__' || $1;

  FOR pkc IN EXECUTE $f$ SELECT attname
                           FROM pg_attribute JOIN
                                pg_class ON (oid = attrelid) JOIN
                                pg_index on (pg_class.oid = pg_index.indrelid and attnum = any (indkey))
                          WHERE pg_class.oid = '$f$ || $1 || $f$ '::regclass and indisprimary $f$
  LOOP
     IF pkcols = '' THEN
        pkcols = quote_ident(pkc.attname);
        pkformat = '%';
     ELSE
        pkcols = pkcols || ', ' || quote_ident(pkc.attname);
        pkformat = pkformat || ', %';
     END IF;
     pk_col_ary = array_append(pk_col_ary, quote_ident(pkc.attname));
  END LOOP;

  /*
   * This is the function header.  It's basically a constant string, with the
   * table name replaced a couple of times and the primary key columns replaced
   * once.  Make sure we don't fail if there's no primary key.
   */
  IF pkcols <> '' THEN
     pkcols = ', ' || pkcols;
     pkformat = ', PK=( ' || pkformat || ' )';
  END IF;
  func = $f$
    CREATE OR REPLACE FUNCTION $f$ || funcname || $f$() RETURNS void LANGUAGE plpgsql AS $$
     DECLARE
       rec record;
     BEGIN
     FOR rec IN SELECT ctid $f$ || pkcols || $f$ FROM $f$ || $1 || $f$ LOOP
        DECLARE
          f record;
          l int;
        BEGIN
          SELECT * INTO f FROM $f$ || $1 || $f$ WHERE ctid = rec.ctid;

          -- make sure each column is detoasted and reported separately
$f$;

   /* We now need one exception block per toastable column */
   indent = '          ';
   FOR column in SELECT attname
                 FROM pg_attribute JOIN pg_class on (oid=attrelid)
                 WHERE pg_class.oid = $1::regclass and attlen = -1
   LOOP
      func := func || indent || E'BEGIN\n';
      func := func || indent || $f$  SELECT length(f.$f$ ||
              quote_ident(column.attname) || E') INTO l;\n';

     /* The interesting part here needs some replacement of the PK columns */
     func := func || indent || $f$EXCEPTION WHEN OTHERS THEN
	    RAISE NOTICE 'TID %$f$ || pkformat || $f$, column "$f$ || column.attname || $f$": exception {{%}}',
			     rec.ctid, $f$;

     /* This iterates zero times if there are no PK columns */
     FOR colrec IN SELECT f.i[a] AS pknm
		  FROM (select pk_col_ary as i) as f,
		       generate_series(array_lower(pk_col_ary, 1), array_upper(pk_col_ary, 1)) as a
     LOOP
       func := func || $f$ rec.$f$ || colrec.pknm || $f$, $f$;
     END LOOP;

     func := func || E'sqlerrm;\n';
     func := func || indent || E'END;\n';
   
   END LOOP;

   /* And this is our constant footer */
   func := func || $f$ 
       END;
     END LOOP;
     END;
    $$;
  $f$;

  EXECUTE func;
  RAISE NOTICE $f$Successfully created function %()$f$, funcname;
  RETURN;
  END;
$qf_toastcheck_writer$;



