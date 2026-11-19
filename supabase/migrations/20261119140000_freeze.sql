-- Fin du voyage : base figée. Plus aucune écriture depuis le site (même une vieille version de l'app), plus de notifs.
-- Les lectures restent possibles (export / archive). Pour annuler : re-grant execute ... to anon sur les mêmes fonctions.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'add_beer','remove_beer','set_beer_brand','set_beer_photo','add_cig','edit_cig','remove_cig','set_avatar',
      'save_push_sub','delete_push_sub','admin_add_beer','admin_remove_last','admin_set_deleted','admin_set_time','admin_push')
  loop
    execute format('revoke execute on function %s from anon, authenticated, public', f.sig);
  end loop;
end $$;

select cron.unschedule(jobname) from cron.job where jobname in ('airport-beer', 'beer-notifs', 'wrapped-notif');
