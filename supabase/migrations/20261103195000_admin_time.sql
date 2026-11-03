-- Menu admin : corriger l'heure d'un verre (ajouté en retard, etc.)
create or replace function public.admin_set_time(p_admin text, p_id uuid, p_at bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform admin_guard(p_admin);
  if p_at is null or p_at > (extract(epoch from now()) * 1000)::bigint + 300000
     or p_at < (extract(epoch from timestamptz '2026-10-01 00:00+00') * 1000)::bigint then
    raise exception 'heure invalide' using errcode = '22023';
  end if;
  update beers set at = p_at where id = p_id;
end $$;
revoke execute on function public.admin_set_time(text, uuid, bigint) from public;
grant execute on function public.admin_set_time(text, uuid, bigint) to anon;
