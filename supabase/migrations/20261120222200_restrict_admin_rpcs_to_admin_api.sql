do $$
declare item record;
begin
  for item in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'admin\_%' escape '\'
      and not (p.proname = 'admin_moderate_user' and p.pronargs = 7)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', item.signature);
    execute format('grant execute on function %s to service_role', item.signature);
  end loop;
end $$;
