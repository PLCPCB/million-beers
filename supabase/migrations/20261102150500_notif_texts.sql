-- Textes des notifs de bières : « au compteur » plutôt que « la bande »

create or replace function public.on_beer_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare total int; nm text; each_p jsonb;
begin
  select count(*) into total from beers where deleted_at is null;
  nm := case new.who when 'alex' then 'Alex' when 'louis' then 'Louis' when 'felix' then 'Félix'
                     when 'pilou' then 'Pilou' when 'noah' then 'Noah' when 'paulin' then 'Paulin' end;
  each_p := jsonb_build_object('title', '🍺 ' || nm || ' · +1', 'body', 'Bière n°' || total || ' au compteur. Bing chilling 冰淇淋', 'tag', 'beer');
  if total % 10 = 0 then
    perform push_send(subs_json('milestone', new.who),
      jsonb_build_object('title', '🎆 ' || total || ' bières au compteur !', 'body', nm || ' fait tomber la ' || total || 'e. MÉGA GANBEI 干杯 !', 'tag', 'milestone'));
    perform push_send((select jsonb_agg(x) from jsonb_array_elements(subs_json('each', new.who)) x
                       where x not in (select jsonb_array_elements(coalesce(subs_json('milestone', new.who), '[]')))), each_p);
  else
    perform push_send(subs_json('each', new.who), each_p);
  end if;
  return new;
exception when others then
  return new;
end $$;
revoke execute on function public.on_beer_insert() from public, anon, authenticated;
