-- Photos de bières : une photo (facultative) par bière, visible seulement avec le code crew.
-- Chaque photo est stockée en deux tailles (data URL JPEG) : une miniature (~10 Ko) pour le Journal
-- et le Wrapped, et l'image complète (~150 Ko) chargée seulement quand on l'ouvre.
-- La table n'est pas lisible directement depuis le site : tout passe par les fonctions ci-dessous.

create table if not exists public.beer_photos (
  beer_id    uuid primary key references public.beers(id) on delete cascade,
  who        text not null,
  thumb      text not null,
  img        text not null,
  updated_at timestamptz not null default now()
);
alter table public.beer_photos enable row level security;
revoke all on public.beer_photos from anon, authenticated;

-- Ajouter / remplacer (p_img non nul) ou retirer (p_img nul) la photo d'une bière.
-- Renvoie false si la bière n'est pas (encore) sur le serveur ou a été retirée.
create or replace function public.set_beer_photo(p_crew text, p_beer uuid, p_thumb text, p_img text)
returns boolean language plpgsql security definer set search_path = public as $$
declare w text;
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  if p_img is null then
    delete from beer_photos where beer_id = p_beer;
    return true;
  end if;
  if p_img not like 'data:image/jpeg;base64,%' or length(p_img) > 450000
     or p_thumb is null or p_thumb not like 'data:image/jpeg;base64,%' or length(p_thumb) > 40000 then
    raise exception 'image invalide' using errcode = '22023';
  end if;
  select b.who into w from beers b where b.id = p_beer and b.deleted_at is null;
  if not found then return false; end if;
  insert into beer_photos(beer_id, who, thumb, img) values (p_beer, w, p_thumb, p_img)
  on conflict (beer_id) do update set thumb = excluded.thumb, img = excluded.img, updated_at = now();
  return true;
end $$;

-- Liste légère : {beer_id: version}, pour savoir quelles miniatures charger.
create or replace function public.list_beer_photos(p_crew text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  return coalesce((select jsonb_object_agg(p.beer_id, floor(extract(epoch from p.updated_at) * 1000)::bigint)
                   from beer_photos p join beers b on b.id = p.beer_id where b.deleted_at is null), '{}'::jsonb);
end $$;

-- Miniatures demandées : {beer_id: data URL}
create or replace function public.get_beer_thumbs(p_crew text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  return coalesce((select jsonb_object_agg(beer_id, thumb) from beer_photos where beer_id = any(p_ids[1:60])), '{}'::jsonb);
end $$;

-- Image complète d'une bière
create or replace function public.get_beer_photo(p_crew text, p_beer uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  return (select img from beer_photos where beer_id = p_beer);
end $$;

revoke execute on function public.set_beer_photo(text, uuid, text, text) from public;
revoke execute on function public.list_beer_photos(text) from public;
revoke execute on function public.get_beer_thumbs(text, uuid[]) from public;
revoke execute on function public.get_beer_photo(text, uuid) from public;
grant execute on function public.set_beer_photo(text, uuid, text, text) to anon;
grant execute on function public.list_beer_photos(text) to anon;
grant execute on function public.get_beer_thumbs(text, uuid[]) to anon;
grant execute on function public.get_beer_photo(text, uuid) to anon;
