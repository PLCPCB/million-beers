-- Notifications push : abonnements, envoi à chaque bière, alertes airport beer.
-- Les secrets (clés VAPID, secret du hook) ne sont PAS ici : ils sont dans Supabase (voir README).

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Abonnements (un par téléphone). Illisibles depuis le site.
create table if not exists public.push_subs (
  endpoint   text primary key,
  p256dh     text not null,
  auth       text not null,
  who        text check (who in ('alex','louis','felix','pilou','noah','paulin')),
  prefs      jsonb not null default '{"each": false, "milestone": true, "airport": true}',
  updated_at timestamptz not null default now()
);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;

-- Secret partagé avec la fonction d'envoi (rempli à la main, hors dépôt)
create table if not exists public.hook_secret (secret text primary key);
alter table public.hook_secret enable row level security;
revoke all on public.hook_secret from anon, authenticated;

-- Vols (pour les alertes airport beer) et alertes déjà envoyées
create table if not exists public.flights (code text primary key, dep timestamptz not null, tz text not null, who text[] not null);
alter table public.flights enable row level security;
revoke all on public.flights from anon, authenticated;
insert into public.flights(code, dep, tz, who) values
  ('GF018',  '2026-11-03 10:50+01', 'Europe/Paris',  array['felix','paulin','pilou']),
  ('AF116',  '2026-11-03 23:20+01', 'Europe/Paris',  array['alex','noah','louis']),
  ('FM9341', '2026-11-07 17:05+08', 'Asia/Shanghai', array['alex','louis','felix','pilou','noah','paulin']),
  ('CA457',  '2026-11-16 01:40+08', 'Asia/Shanghai', array['pilou']),
  ('CA4535', '2026-11-16 18:00+08', 'Asia/Shanghai', array['alex','louis','felix','noah','paulin']),
  ('GF125',  '2026-11-18 16:30+08', 'Asia/Shanghai', array['felix','paulin']),
  ('AF111',  '2026-11-18 22:15+08', 'Asia/Shanghai', array['alex','noah','louis'])
on conflict (code) do update set dep = excluded.dep, tz = excluded.tz, who = excluded.who;

create table if not exists public.alerts_sent (key text primary key, at timestamptz not null default now());
alter table public.alerts_sent enable row level security;
revoke all on public.alerts_sent from anon, authenticated;

-- Le site : s'abonner / se désabonner (avec le code de la bande)
create or replace function public.save_push_sub(p_crew text, p_endpoint text, p_p256dh text, p_auth text, p_who text, p_prefs jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  if p_endpoint not like 'https://%' or length(p_endpoint) > 1000 or length(p_p256dh) > 200 or length(p_auth) > 100 then
    raise exception 'abonnement invalide' using errcode = '22023';
  end if;
  insert into push_subs(endpoint, p256dh, auth, who, prefs, updated_at)
  values (p_endpoint, p_p256dh, p_auth, nullif(p_who, ''), coalesce(p_prefs, '{}'::jsonb), now())
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, who = excluded.who, prefs = excluded.prefs, updated_at = now();
end $$;

create or replace function public.delete_push_sub(p_crew text, p_endpoint text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  delete from push_subs where endpoint = p_endpoint;
end $$;

-- La fonction d'envoi : retirer les abonnements morts
create or replace function public.drop_push_subs(p_secret text, p_endpoints text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from hook_secret where secret = p_secret) then
    raise exception 'secret invalide' using errcode = '42501';
  end if;
  delete from push_subs where endpoint = any(p_endpoints);
end $$;

-- Interne : envoie une notif à une liste d'abonnements via la fonction « notify »
create or replace function public.push_send(p_subs jsonb, p_payload jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_subs is null or jsonb_array_length(p_subs) = 0 then return; end if;
  perform net.http_post(
    url     := 'https://aqpxywxolmyyndkezhfn.supabase.co/functions/v1/notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', (select secret from hook_secret limit 1)),
    body    := jsonb_build_object('subs', p_subs, 'payload', p_payload)
  );
end $$;

create or replace function public.subs_json(p_filter text, p_who text, p_flight text[] default null)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'keys', jsonb_build_object('p256dh', p256dh, 'auth', auth)))
  from push_subs
  where case p_filter
    when 'each'      then coalesce((prefs->>'each')::boolean, false) and who is distinct from p_who
    when 'milestone' then coalesce((prefs->>'milestone')::boolean, true) and who is distinct from p_who
    when 'airport'   then coalesce((prefs->>'airport')::boolean, true) and who = any(p_flight)
  end;
$$;

-- À chaque nouvelle bière
create or replace function public.on_beer_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare total int; nm text;
begin
  select count(*) into total from beers where deleted_at is null;
  nm := case new.who when 'alex' then 'Alex' when 'louis' then 'Louis' when 'felix' then 'Félix'
                     when 'pilou' then 'Pilou' when 'noah' then 'Noah' when 'paulin' then 'Paulin' end;
  if total % 10 = 0 then
    perform push_send(subs_json('milestone', new.who),
      jsonb_build_object('title', '🎆 ' || total || ' bières pour la bande !', 'body', nm || ' fait tomber la ' || total || 'e. MÉGA GANBEI 干杯 !', 'tag', 'milestone'));
    -- ceux qui veulent chaque bière mais pas les paliers la reçoivent quand même
    perform push_send((select jsonb_agg(x) from jsonb_array_elements(subs_json('each', new.who)) x
                       where x not in (select jsonb_array_elements(coalesce(subs_json('milestone', new.who), '[]')))),
      jsonb_build_object('title', '🍺 ' || nm || ' · +1', 'body', 'Bière n°' || total || ' de la bande. Bing chilling 冰淇淋', 'tag', 'beer'));
  else
    perform push_send(subs_json('each', new.who),
      jsonb_build_object('title', '🍺 ' || nm || ' · +1', 'body', 'Bière n°' || total || ' de la bande. Bing chilling 冰淇淋', 'tag', 'beer'));
  end if;
  return new;
exception when others then
  return new;   -- une notif ratée ne doit jamais bloquer une bière
end $$;

drop trigger if exists beers_notify on public.beers;
create trigger beers_notify after insert on public.beers for each row execute function public.on_beer_insert();

-- Toutes les 5 minutes : fenêtres airport beer (ouverture à H-3, dernière heure à H-1)
create or replace function public.airport_tick()
returns void language plpgsql security definer set search_path = public as $$
declare f record; k text; t text;
begin
  for f in select * from flights where now() between dep - interval '3 hours' and dep loop
    t := to_char(f.dep at time zone f.tz, 'HH24:MI');
    k := f.code || ':open';
    if now() < f.dep - interval '2 hours' and not exists (select 1 from alerts_sent where key = k) then
      insert into alerts_sent(key) values (k);
      perform push_send(subs_json('airport', null, f.who),
        jsonb_build_object('title', '✈ Fenêtre airport beer ouverte', 'body', f.code || ' décolle à ' || t || '. 3 h pour une petite pour la route 干杯', 'tag', 'airport-' || f.code));
    end if;
    k := f.code || ':last';
    if now() >= f.dep - interval '1 hour' and now() < f.dep - interval '20 minutes' and not exists (select 1 from alerts_sent where key = k) then
      insert into alerts_sent(key) values (k);
      perform push_send(subs_json('airport', null, f.who),
        jsonb_build_object('title', '⏳ Dernière heure pour une airport beer', 'body', f.code || ' décolle à ' || t || '. Cul sec 一口闷 !', 'tag', 'airport-' || f.code));
    end if;
  end loop;
end $$;

revoke execute on function public.push_send(jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.subs_json(text, text, text[]) from public, anon, authenticated;
revoke execute on function public.on_beer_insert() from public, anon, authenticated;
revoke execute on function public.airport_tick() from public, anon, authenticated;
revoke execute on function public.save_push_sub(text, text, text, text, text, jsonb) from public;
revoke execute on function public.delete_push_sub(text, text) from public;
revoke execute on function public.drop_push_subs(text, text[]) from public;
grant execute on function public.save_push_sub(text, text, text, text, text, jsonb) to anon;
grant execute on function public.delete_push_sub(text, text) to anon;
grant execute on function public.drop_push_subs(text, text[]) to anon;

select cron.schedule('airport-beer', '*/5 * * * *', 'select public.airport_tick()');

-- À faire à la main après une restauration (hors dépôt) :
--   insert into hook_secret(secret) values ('<même valeur que HOOK_SECRET dans les secrets des Edge Functions>');
