-- Notif « Ganbei Wrapped est prêt », une seule fois, le 19/11 à 7 h heure de Paris (06:00 UTC),
-- au moment où le Wrapped s'ouvre dans l'app. La tâche se retire d'elle-même après l'envoi.
create or replace function public.wrapped_notif()
returns int language plpgsql security definer set search_path = public, extensions as $$
declare subs jsonb; n int;
begin
  if now() < timestamptz '2026-11-19 06:00+00' then return 0; end if;
  select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'keys', jsonb_build_object('p256dh', p256dh, 'auth', auth))), count(*)
    into subs, n from push_subs;
  perform push_send(subs, jsonb_build_object(
    'title', '🎁 Ganbei Wrapped est prêt',
    'body', 'Le grand récap du voyage vous attend : classement final, records, mur des bières et Clopédex. 干杯 !',
    'tag', 'wrapped'));
  perform cron.unschedule('wrapped-notif');
  return coalesce(n, 0);
end $$;
revoke execute on function public.wrapped_notif() from public, anon, authenticated;

select cron.schedule('wrapped-notif', '0 6 19 11 *', 'select public.wrapped_notif()');
