-- Clopédex : couleur du paquet (cadre et sceau de la carte). Vide = calculée par le téléphone à partir de la photo.
alter table public.cigs add column if not exists color text not null default '';

create or replace function public.cig_check_color(p_color text)
returns void language plpgsql as $$
begin
  if coalesce(p_color, '') not in ('', 'rouge', 'orange', 'or', 'vert', 'bleu', 'violet', 'rose', 'blanc', 'noir') then
    raise exception 'couleur invalide' using errcode = '22023';
  end if;
end $$;
revoke execute on function public.cig_check_color(text) from public, anon, authenticated;

-- nouvelles versions avec p_color (les anciennes restent pour les téléphones pas encore mis à jour)
create or replace function public.add_cig(p_crew text, p_id uuid, p_who text, p_name text, p_note text, p_city text, p_at bigint, p_color text, p_thumb text, p_img text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  perform cig_check_img(p_thumb, p_img);
  perform cig_check_color(p_color);
  if length(coalesce(p_name, '')) > 40 or length(coalesce(p_note, '')) > 140
     or coalesce(p_city, '') not in ('', 'shanghai', 'zhangjiajie', 'chongqing', 'chengdu', 'autre') then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  insert into cigs(id, who, name, note, city, at, color, thumb, img)
  values (p_id, p_who, coalesce(p_name, ''), coalesce(p_note, ''), coalesce(p_city, ''), p_at, coalesce(p_color, ''), p_thumb, p_img)
  on conflict (id) do nothing;
end $$;

create or replace function public.edit_cig(p_crew text, p_id uuid, p_name text, p_note text, p_city text, p_who text, p_color text, p_thumb text, p_img text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  perform cig_check_color(p_color);
  if length(coalesce(p_name, '')) > 40 or length(coalesce(p_note, '')) > 140
     or coalesce(p_city, '') not in ('', 'shanghai', 'zhangjiajie', 'chongqing', 'chengdu', 'autre')
     or (p_who is not null and p_who not in ('alex','louis','felix','pilou','noah','paulin')) then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  if p_img is not null then perform cig_check_img(p_thumb, p_img); end if;
  update cigs set name = coalesce(p_name, ''), note = coalesce(p_note, ''), city = coalesce(p_city, ''), who = coalesce(p_who, who),
                  color = coalesce(p_color, color), thumb = coalesce(p_thumb, thumb), img = coalesce(p_img, img), updated_at = now()
  where id = p_id and deleted_at is null;
end $$;

create or replace function public.list_cigs(p_crew text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'who', who, 'name', name, 'note', note, 'city', city, 'at', at, 'color', color,
                                                       'v', floor(extract(epoch from updated_at) * 1000)::bigint) order by at)
                   from cigs where deleted_at is null), '[]'::jsonb);
end $$;

revoke execute on function public.add_cig(text, uuid, text, text, text, text, bigint, text, text, text) from public;
revoke execute on function public.edit_cig(text, uuid, text, text, text, text, text, text, text) from public;
grant execute on function public.add_cig(text, uuid, text, text, text, text, bigint, text, text, text) to anon;
grant execute on function public.edit_cig(text, uuid, text, text, text, text, text, text, text) to anon;
