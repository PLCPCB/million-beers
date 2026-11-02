-- Rappels de check-in (24-48 h avant chaque vol, seulement pour ceux qui le prennent)
-- + appel de la fonction « notify » avec la clé publique anon (vérification JWT laissée active).

create or replace function public.push_send(p_subs jsonb, p_payload jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_subs is null or jsonb_array_length(p_subs) = 0 then return; end if;
  perform net.http_post(
    url     := 'https://aqpxywxolmyyndkezhfn.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      -- clé « anon » : publique par nature, elle sert juste à passer la vérification JWT de la fonction
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxcHh5d3hvbG15eW5ka2V6aGZuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1NTY2NzMsImV4cCI6MjEwOTEzMjY3M30.BNWMmIeJ8YbF0S6fNwk0aJe4jGKSCl36ON7LWjI23CA',
      'x-hook-secret', (select secret from hook_secret limit 1)),
    body    := jsonb_build_object('subs', p_subs, 'payload', p_payload)
  );
end $$;
revoke execute on function public.push_send(jsonb, jsonb) from public, anon, authenticated;

create table if not exists public.reminders (
  key text primary key, flight text not null references public.flights(code), send_at timestamptz not null,
  who text[] not null, title text not null, body text not null
);
alter table public.reminders enable row level security;
revoke all on public.reminders from anon, authenticated;

create table if not exists public.reminder_log (rkey text not null, endpoint text not null, at timestamptz not null default now(), primary key (rkey, endpoint));
alter table public.reminder_log enable row level security;
revoke all on public.reminder_log from anon, authenticated;

insert into public.reminders(key, flight, send_at, who, title, body) values
  ('GF018',  'GF018',  '2026-11-02 15:00+01', array['felix','paulin','pilou'],
   '🧳 Demain 10:50 · check-in GF018', 'Paris CDG → Bahreïn → Shanghai. Check-in en ligne, carte d''arrivée remplie, passeport dans la poche.'),
  ('AF116',  'AF116',  '2026-11-02 15:00+01', array['alex','noah','louis'],
   '🧳 Demain 23:20 · check-in AF116', 'Paris CDG → Shanghai. Pense au check-in en ligne, à la carte d''arrivée et au passeport.'),
  ('FM9341', 'FM9341', '2026-11-06 10:00+08', array['alex','louis','felix','pilou','noah','paulin'],
   '🧳 Demain 17:05 · check-in FM9341', 'Shanghai PVG → Zhangjiajie. Bagage cabine souvent limité à 5 kg, batteries externes avec logo 3C en cabine.'),
  ('CA457',  'CA457',  '2026-11-14 10:00+08', array['pilou'],
   '🧳 Lundi 01:40 · check-in CA457', 'Chengdu TFU (Tianfu, pas Shuangliu) → Paris CDG. Départ de l''hôtel dimanche vers 22 h.'),
  ('CA4535', 'CA4535', '2026-11-15 10:00+08', array['alex','louis','felix','noah','paulin'],
   '🧳 Demain 18:00 · check-in CA4535', 'Chengdu CTU (Shuangliu) → Shanghai PVG. Bagage cabine souvent limité à 5 kg.'),
  ('GF125',  'GF125',  '2026-11-17 10:00+08', array['felix','paulin'],
   '🧳 Demain 16:30 · check-in GF125', 'Shanghai PVG → Bahreïn → Paris. Dernière soirée à Shanghai, dernière ligne droite vers le million.'),
  ('AF111',  'AF111',  '2026-11-17 10:00+08', array['alex','noah','louis'],
   '🧳 Demain 22:15 · check-in AF111', 'Shanghai PVG → Paris CDG. Dernière soirée à Shanghai, dernière ligne droite vers le million.')
on conflict (key) do update set flight = excluded.flight, send_at = excluded.send_at, who = excluded.who, title = excluded.title, body = excluded.body;

-- Envoie les rappels dus ; un téléphone abonné en retard les reçoit aussi, tant que le vol n'est pas parti.
create or replace function public.reminders_tick()
returns void language plpgsql security definer set search_path = public as $$
declare r record; subs jsonb; eps text[];
begin
  for r in select m.*, f.dep from reminders m join flights f on f.code = m.flight where m.send_at <= now() and now() < f.dep loop
    select jsonb_agg(jsonb_build_object('endpoint', p.endpoint, 'keys', jsonb_build_object('p256dh', p.p256dh, 'auth', p.auth))), array_agg(p.endpoint)
      into subs, eps
      from push_subs p
      where p.who = any(r.who) and coalesce((p.prefs->>'checkin')::boolean, true)
        and not exists (select 1 from reminder_log l where l.rkey = r.key and l.endpoint = p.endpoint);
    if eps is not null then
      perform push_send(subs, jsonb_build_object('title', r.title, 'body', r.body, 'tag', 'checkin-' || r.flight));
      insert into reminder_log(rkey, endpoint) select r.key, unnest(eps) on conflict do nothing;
    end if;
  end loop;
end $$;

create or replace function public.cron_tick()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform airport_tick();
  perform reminders_tick();
end $$;
revoke execute on function public.reminders_tick() from public, anon, authenticated;
revoke execute on function public.cron_tick() from public, anon, authenticated;

select cron.schedule('airport-beer', '*/5 * * * *', 'select public.cron_tick()');
