-- Notifs de bières envoyées 10 s après le +1 : une bière annulée entre-temps ne notifie personne.

create table if not exists public.beer_notif_queue (
  beer_id uuid primary key,
  total   int not null,
  due_at  timestamptz not null
);
alter table public.beer_notif_queue enable row level security;
revoke all on public.beer_notif_queue from anon, authenticated;

create or replace function public.on_beer_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare total int;
begin
  select count(*) into total from beers where deleted_at is null;
  insert into beer_notif_queue(beer_id, total, due_at) values (new.id, total, now() + interval '10 seconds')
  on conflict do nothing;
  return new;
exception when others then
  return new;   -- une notif ratée ne doit jamais bloquer une bière
end $$;

create or replace function public.flush_beer_notifs()
returns void language plpgsql security definer set search_path = public as $$
declare q record; b record; nm text; each_p jsonb;
begin
  for q in delete from beer_notif_queue where due_at <= now() returning * loop
    select * into b from beers where id = q.beer_id and deleted_at is null;
    if not found then continue; end if;          -- annulée entre-temps
    nm := case b.who when 'alex' then 'Alex' when 'louis' then 'Louis' when 'felix' then 'Félix'
                     when 'pilou' then 'Pilou' when 'noah' then 'Noah' when 'paulin' then 'Paulin' end;
    each_p := jsonb_build_object('title', '🍺 ' || nm || ' · +1', 'body', 'Bière n°' || q.total || ' au compteur. Bing chilling 冰淇淋', 'tag', 'beer');
    if q.total % 10 = 0 then
      perform push_send(subs_json('milestone', b.who),
        jsonb_build_object('title', '🎆 ' || q.total || ' bières au compteur !', 'body', nm || ' fait tomber la ' || q.total || 'e. MÉGA GANBEI 干杯 !', 'tag', 'milestone'));
      perform push_send((select jsonb_agg(x) from jsonb_array_elements(subs_json('each', b.who)) x
                         where x not in (select jsonb_array_elements(coalesce(subs_json('milestone', b.who), '[]')))), each_p);
    else
      perform push_send(subs_json('each', b.who), each_p);
    end if;
  end loop;
end $$;

revoke execute on function public.on_beer_insert() from public, anon, authenticated;
revoke execute on function public.flush_beer_notifs() from public, anon, authenticated;

select cron.schedule('beer-notifs', '5 seconds', 'select public.flush_beer_notifs()');
