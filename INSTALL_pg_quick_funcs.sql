--
-- "Package": pg_quick_funcs
--

-- LAWS:
--   * All the fuckin' functions should start with "qf_", that's the prefix, don't mess it up!
--   * Any time you add a function here, add its DROP sentence in the uninstall_pg_quick_funcs.sql 
       or to the qf_uninstall_qf().
--   * Keep decent names. Not those you choose for you kids.
--   * Keep sql and plsql languages. 
--   * Keep the definition with the funciton name in the middle.



CREATE OR REPLACE FUNCTION qf_help() RETURNS NULL $qf_help$
BEGIN
    RAISE NOTICE ' Help(): ';
    RAISE NOTICE '    qf_help()                 -> This function, idiot.';
END;
$qf_help$ LANGUAGE plpgsql;


