-- Explicitly place pg_temp after trusted schemas for SECURITY DEFINER functions.
-- PostgreSQL otherwise searches the temporary schema first for relations when pg_temp
-- is omitted from search_path, which can allow object shadowing by callers with temp access.

do $migration$
declare
  target record;
begin
  for target in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef
      and n.nspname in ('public', 'private')
      and exists (
        select 1
        from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
          and cfg not like '%pg_temp%'
          and cfg <> 'search_path=""'
      )
  loop
    execute format(
      'alter function %s set search_path to pg_catalog, public, pg_temp',
      target.signature
    );
  end loop;
end
$migration$;
