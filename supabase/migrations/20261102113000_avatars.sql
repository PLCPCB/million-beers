-- Photos de profil : une par personne, visibles par tous, modifiables avec le code de la bande.
-- L'image est un petit JPEG rond-prêt (256 px, ~15 Ko) stocké en texte (data URL).

create table if not exists public.avatars (
  who        text primary key check (who in ('alex','louis','felix','pilou','noah','paulin')),
  img        text not null,
  updated_at timestamptz not null default now()
);

alter table public.avatars enable row level security;
drop policy if exists "lecture" on public.avatars;
create policy "lecture" on public.avatars for select to anon using (true);
revoke all on public.avatars from anon, authenticated;
grant select on public.avatars to anon;

-- p_img = null : retour à l'emoji
create or replace function public.set_avatar(p_who text, p_img text, p_crew text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crew_secret where code = p_crew) then
    raise exception 'code crew invalide' using errcode = '42501';
  end if;
  if p_who not in ('alex','louis','felix','pilou','noah','paulin') then
    raise exception 'personne inconnue' using errcode = '22023';
  end if;
  if p_img is null then
    delete from avatars where who = p_who;
    return;
  end if;
  if p_img not like 'data:image/jpeg;base64,%' or length(p_img) > 120000 then
    raise exception 'image invalide' using errcode = '22023';
  end if;
  insert into avatars(who, img) values (p_who, p_img)
  on conflict (who) do update set img = excluded.img, updated_at = now();
end $$;

revoke execute on function public.set_avatar(text, text, text) from public;
grant execute on function public.set_avatar(text, text, text) to anon;
