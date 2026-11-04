-- Clopédex : réattribuer une trouvaille (« Trouvé par »). Nouvelle version de edit_cig avec p_who ;
-- l'ancienne (sans p_who) reste pour les téléphones pas encore mis à jour.
create or replace function public.edit_cig(p_crew text, p_id uuid, p_name text, p_note text, p_city text, p_who text, p_thumb text, p_img text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cig_guard(p_crew);
  if length(coalesce(p_name, '')) > 40 or length(coalesce(p_note, '')) > 140
     or coalesce(p_city, '') not in ('', 'shanghai', 'zhangjiajie', 'chongqing', 'chengdu', 'autre')
     or (p_who is not null and p_who not in ('alex','louis','felix','pilou','noah','paulin')) then
    raise exception 'texte invalide' using errcode = '22023';
  end if;
  if p_img is not null then perform cig_check_img(p_thumb, p_img); end if;
  update cigs set name = coalesce(p_name, ''), note = coalesce(p_note, ''), city = coalesce(p_city, ''), who = coalesce(p_who, who),
                  thumb = coalesce(p_thumb, thumb), img = coalesce(p_img, img), updated_at = now()
  where id = p_id and deleted_at is null;
end $$;
revoke execute on function public.edit_cig(text, uuid, text, text, text, text, text, text) from public;
grant execute on function public.edit_cig(text, uuid, text, text, text, text, text, text) to anon;
