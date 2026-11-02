-- Liens réservés à la bande (ex. le carnet de voyage).
-- Les adresses vivent uniquement dans cette table : jamais dans le dépôt ni dans la page.
-- Le site les demande avec le code de la bande ; sans code, rien n'est renvoyé.

create table if not exists public.band_links (
  key text primary key,      -- ex. 'carnet'
  url text not null check (url like 'https://%')
);
alter table public.band_links enable row level security;
revoke all on public.band_links from anon, authenticated;   -- aucune lecture directe

create or replace function public.get_links(p_crew text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  return coalesce((select json_object_agg(key, url) from band_links), '{}'::json);
end $$;

revoke execute on function public.get_links(text) from public;
grant execute on function public.get_links(text) to anon;

-- Après une restauration, remettre le lien à la main (hors dépôt) :
--   insert into band_links(key, url) values ('carnet', 'https://docs.google.com/...')
--   on conflict (key) do update set url = excluded.url;
