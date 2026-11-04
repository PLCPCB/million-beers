-- Clopédex 烟谱 : la collection de paquets (et de clopes) trouvés pendant le voyage. Pas de compétition, juste la collection.
-- Une photo par entrée, en deux tailles (miniature pour la grille, image complète à l'ouverture).
-- Visible et modifiable seulement avec le code crew ; la table n'est pas lisible directement depuis le site.

create table if not exists public.cigs (
  id         uuid primary key,                       -- généré par le téléphone
  who        text not null check (who in ('alex','louis','felix','pilou','noah','paulin')),
  name       text not null default '',
  note       text not null default '',
  city       text not null default '',
  at         bigint not null,                         -- moment de la trouvaille (ms)
  thumb      text not null,
  img        text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.cigs enable row level security;
revoke all on public.cigs from anon, authenticated;

create or replace function public.cig_guard(p_crew text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
end $$;
revoke execute on function public.cig_guard(text) from public, anon, authenticated;

create or replace function public.cig_check_img(p_thumb text, p_img text)
returns void language plpgsql as $$
begin
  if p_img not like 'data:image/jpeg;base64,%' or length(p_img) > 450000
     or p_thumb not like 'data:image/jpeg;base64,%' or length(p_thumb) > 40000 then
    raise exception 'image invalide' using errcode = '22023';
  end if;
end $$;
revoke execute on function public.cig_check_img(text, text) from public, anon, authenticated;

create or replace function public.add_cig(p_crew text, p_id uuid, p_who text, p_name text, p_note text, p_city text, p_at bigint, p_thumb text, p_img text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  perform cig_check_img(p_thumb, p_img);
  if length(coalesce(p_name, '')) > 40 or length(coalesce(p_note, '')) > 140
     or coalesce(p_city, '') not in ('', 'shanghai', 'zhangjiajie', 'chongqing', 'chengdu', 'autre') then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  insert into cigs(id, who, name, note, city, at, thumb, img)
  values (p_id, p_who, coalesce(p_name, ''), coalesce(p_note, ''), coalesce(p_city, ''), p_at, p_thumb, p_img)
  on conflict (id) do nothing;
end $$;

-- Modifier le nom / le verdict / la ville, et la photo si p_img n'est pas nul
create or replace function public.edit_cig(p_crew text, p_id uuid, p_name text, p_note text, p_city text, p_thumb text, p_img text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  if length(coalesce(p_name, '')) > 40 or length(coalesce(p_note, '')) > 140
     or coalesce(p_city, '') not in ('', 'shanghai', 'zhangjiajie', 'chongqing', 'chengdu', 'autre') then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  if p_img is not null then perform cig_check_img(p_thumb, p_img); end if;
  update cigs set name = coalesce(p_name, ''), note = coalesce(p_note, ''), city = coalesce(p_city, ''),
                  thumb = coalesce(p_thumb, thumb), img = coalesce(p_img, img), updated_at = now()
  where id = p_id and deleted_at is null;
end $$;

create or replace function public.remove_cig(p_crew text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  update cigs set deleted_at = now() where id = p_id and deleted_at is null;
end $$;

-- Liste légère (sans images) ; v = version pour savoir quelle miniature recharger
create or replace function public.list_cigs(p_crew text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'who', who, 'name', name, 'note', note, 'city', city, 'at', at,
                                                       'v', floor(extract(epoch from updated_at) * 1000)::bigint) order by at)
                   from cigs where deleted_at is null), '[]'::jsonb);
end $$;

create or replace function public.get_cig_thumbs(p_crew text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  return coalesce((select jsonb_object_agg(id, thumb) from cigs where id = any(p_ids[1:60])), '{}'::jsonb);
end $$;

create or replace function public.get_cig_photo(p_crew text, p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  return (select img from cigs where id = p_id and deleted_at is null);
end $$;

revoke execute on function public.add_cig(text, uuid, text, text, text, text, bigint, text, text) from public;
revoke execute on function public.edit_cig(text, uuid, text, text, text, text, text) from public;
revoke execute on function public.remove_cig(text, uuid) from public;
revoke execute on function public.list_cigs(text) from public;
revoke execute on function public.get_cig_thumbs(text, uuid[]) from public;
revoke execute on function public.get_cig_photo(text, uuid) from public;
grant execute on function public.add_cig(text, uuid, text, text, text, text, bigint, text, text) to anon;
grant execute on function public.edit_cig(text, uuid, text, text, text, text, text) to anon;
grant execute on function public.remove_cig(text, uuid) to anon;
grant execute on function public.list_cigs(text) to anon;
grant execute on function public.get_cig_thumbs(text, uuid[]) to anon;
grant execute on function public.get_cig_photo(text, uuid) to anon;
