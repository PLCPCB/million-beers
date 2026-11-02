-- Protection par code de la bande + retraits réversibles

alter table public.beers add column if not exists deleted_at timestamptz;
alter table public.beers alter column brand set default 'biere';

-- Plus aucune écriture directe depuis le site
drop policy if exists "ajout" on public.beers;
drop policy if exists "suppression" on public.beers;
revoke insert, update, delete on public.beers from anon, authenticated;

-- Le code de la bande vit uniquement ici, jamais dans le dépôt.
-- Après une restauration, l'ajouter à la main (voir supabase/README.md).
create table if not exists public.crew_secret (code text primary key);
alter table public.crew_secret enable row level security;
revoke all on public.crew_secret from anon, authenticated;

create or replace function public.add_beer(p_id uuid, p_who text, p_brand text, p_at bigint, p_crew text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  -- refuse les heures absurdes (plus de 3 jours dans le passé ou 1 h dans le futur)
  if p_at < (extract(epoch from now())*1000)::bigint - 3*86400000
     or p_at > (extract(epoch from now())*1000)::bigint + 3600000 then
    raise exception 'heure invalide' using errcode = '22023';
  end if;
  insert into beers(id, who, brand, at) values (p_id, p_who, coalesce(nullif(p_brand, ''), 'biere'), p_at)
  on conflict (id) do nothing;
end $$;

create or replace function public.remove_beer(p_id uuid, p_crew text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  update beers set deleted_at = now() where id = p_id and deleted_at is null;
end $$;

revoke execute on function public.add_beer(uuid, text, text, bigint, text) from public;
revoke execute on function public.remove_beer(uuid, text) from public;
grant execute on function public.add_beer(uuid, text, text, bigint, text) to anon;
grant execute on function public.remove_beer(uuid, text) to anon;
