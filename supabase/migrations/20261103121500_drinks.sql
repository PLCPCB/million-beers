-- Autres verres (vin, cocktail, shot, baijiu) : ils comptent comme une bière, seul le type change.
-- 1) Corriger le type d'un verre déjà envoyé (« c'était un vin, pas une Tsingtao »).
-- 2) Les notifs de chaque verre prennent l'emoji du type (lu 10 s après le +1, donc une correction rapide est prise en compte).

create or replace function public.set_beer_brand(p_id uuid, p_brand text, p_crew text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  if p_brand is null or p_brand !~ '^[a-z]{2,20}$' then
    raise exception 'type invalide' using errcode = '22023';
  end if;
  update beers set brand = p_brand where id = p_id and deleted_at is null;
end $$;
revoke execute on function public.set_beer_brand(uuid, text, text) from public;
grant execute on function public.set_beer_brand(uuid, text, text) to anon;

create or replace function public.flush_beer_notifs()
returns void language plpgsql security definer set search_path = public as $$
declare q record; b record; nm text; em text; kind text; each_p jsonb;
begin
  for q in delete from beer_notif_queue where due_at <= now() returning * loop
    select * into b from beers where id = q.beer_id and deleted_at is null;
    if not found then continue; end if;          -- annulée entre-temps
    nm := case b.who when 'alex' then 'Alex' when 'louis' then 'Louis' when 'felix' then 'Félix'
                     when 'pilou' then 'Pilou' when 'noah' then 'Noah' when 'paulin' then 'Paulin' end;
    em := case b.brand when 'vin' then '🍷' when 'cocktail' then '🍹' when 'shot' then '🥃' when 'baijiu' then '🍶' else '🍺' end;
    kind := case b.brand when 'vin' then ' (un verre de vin)' when 'cocktail' then ' (un cocktail)' when 'shot' then ' (un shot)'
                         when 'baijiu' then ' (un baijiu 白酒)' else '' end;
    each_p := jsonb_build_object('title', em || ' ' || nm || ' · +1', 'body', 'Verre n°' || q.total || ' au compteur' || kind || '. Bing chilling 冰淇淋', 'tag', 'beer');
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
revoke execute on function public.flush_beer_notifs() from public, anon, authenticated;
