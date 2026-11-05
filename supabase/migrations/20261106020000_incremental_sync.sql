-- Synchro légère : le site ne télécharge plus toute la liste des verres toutes les 4 s, seulement ce qui a changé.
alter table public.beers add column if not exists updated_at timestamptz not null default now();
create index if not exists beers_updated_at_idx on public.beers (updated_at);
drop trigger if exists beers_touch on public.beers;
-- les verres existants gardent leur vraie date (sinon ils auraient tous la même et reviendraient à chaque synchro)
update public.beers set updated_at = coalesce(deleted_at, created_at);

create or replace function public.beers_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger beers_touch before update on public.beers for each row execute function public.beers_touch();

-- p_since nul : liste complète. Sinon : tout ce qui a bougé depuis (avec 30 s de recouvrement pour ne rien rater),
-- retraits compris (del = true). max = curseur à renvoyer la prochaine fois.
create or replace function public.beers_since(p_since timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(jsonb_build_object('id', id, 'who', who, 'brand', brand, 'at', at, 'del', deleted_at is not null) order by updated_at), '[]'::jsonb),
    'max',  max(updated_at))
  from beers
  where (p_since is null and deleted_at is null) or (p_since is not null and updated_at > p_since - interval '30 seconds');
$$;
revoke execute on function public.beers_since(timestamptz) from public;
grant execute on function public.beers_since(timestamptz) to anon;
