-- Menu admin (caché dans l'app) : corriger les compteurs, restaurer des bières, notif perso, état des abonnés.
-- Protégé par un code admin distinct du code crew. Le code vit seulement dans Supabase, jamais dans le dépôt :
--   insert into admin_secret(code) values ('<code admin>');

create table if not exists public.admin_secret (code text primary key);
alter table public.admin_secret enable row level security;
revoke all on public.admin_secret from anon, authenticated;

create or replace function public.admin_guard(p_admin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_admin is null or not exists (select 1 from admin_secret where code = p_admin) then
    raise exception 'code admin invalide' using errcode = '42501';
  end if;
end $$;
revoke execute on function public.admin_guard(text) from public, anon, authenticated;

create or replace function public.admin_check(p_admin text)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from admin_secret where code = p_admin);
$$;

-- Ajouter une bière à quelqu'un (sans notif : c'est une correction)
create or replace function public.admin_add_beer(p_admin text, p_who text, p_at bigint)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare nid uuid := gen_random_uuid();
begin
  perform admin_guard(p_admin);
  if p_who not in ('alex','louis','felix','pilou','noah','paulin') then raise exception 'personne inconnue' using errcode = '22023'; end if;
  insert into beers(id, who, brand, at) values (nid, p_who, 'biere', coalesce(p_at, (extract(epoch from now()) * 1000)::bigint));
  delete from beer_notif_queue where beer_id = nid;
  return nid;
end $$;

-- Retirer la dernière bière de quelqu'un ; renvoie son id (pour pouvoir annuler)
create or replace function public.admin_remove_last(p_admin text, p_who text)
returns uuid language plpgsql security definer set search_path = public as $$
declare bid uuid;
begin
  perform admin_guard(p_admin);
  select id into bid from beers where who = p_who and deleted_at is null order by at desc limit 1;
  if bid is null then return null; end if;
  update beers set deleted_at = now() where id = bid;
  return bid;
end $$;

-- Retirer (true) ou restaurer (false) une bière précise
create or replace function public.admin_set_deleted(p_admin text, p_id uuid, p_deleted boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform admin_guard(p_admin);
  update beers set deleted_at = case when p_deleted then now() else null end where id = p_id;
end $$;

-- Notif perso, à tout le monde (p_who nul) ou à certains ; renvoie le nombre de téléphones visés
create or replace function public.admin_push(p_admin text, p_title text, p_body text, p_who text[])
returns int language plpgsql security definer set search_path = public as $$
declare subs jsonb; n int;
begin
  perform admin_guard(p_admin);
  if coalesce(length(p_title), 0) = 0 or length(p_title) > 80 or length(coalesce(p_body, '')) > 300 then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'keys', jsonb_build_object('p256dh', p256dh, 'auth', auth))), count(*)
    into subs, n from push_subs where p_who is null or who = any(p_who);
  perform push_send(subs, jsonb_build_object('title', p_title, 'body', coalesce(p_body, ''), 'tag', 'admin-' || floor(extract(epoch from now()))));
  return coalesce(n, 0);
end $$;

-- État : abonnés aux notifs et dernières bières retirées
create or replace function public.admin_status(p_admin text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform admin_guard(p_admin);
  return jsonb_build_object(
    'subs', coalesce((select jsonb_agg(jsonb_build_object('who', who, 'at', floor(extract(epoch from updated_at) * 1000))) from push_subs), '[]'::jsonb),
    'deleted', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', id, 'who', who, 'at', at, 'del', floor(extract(epoch from deleted_at) * 1000)) x
                         from beers where deleted_at is not null order by deleted_at desc limit 8) t), '[]'::jsonb));
end $$;

revoke execute on function public.admin_check(text) from public;
revoke execute on function public.admin_add_beer(text, text, bigint) from public;
revoke execute on function public.admin_remove_last(text, text) from public;
revoke execute on function public.admin_set_deleted(text, uuid, boolean) from public;
revoke execute on function public.admin_push(text, text, text, text[]) from public;
revoke execute on function public.admin_status(text) from public;
grant execute on function public.admin_check(text) to anon;
grant execute on function public.admin_add_beer(text, text, bigint) to anon;
grant execute on function public.admin_remove_last(text, text) to anon;
grant execute on function public.admin_set_deleted(text, uuid, boolean) to anon;
grant execute on function public.admin_push(text, text, text, text[]) to anon;
grant execute on function public.admin_status(text) to anon;
