-- Permet au site de vérifier un code sans rien écrire

create or replace function public.check_crew(p_crew text)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from crew_secret where code = p_crew);
$$;

revoke execute on function public.check_crew(text) from public;
grant execute on function public.check_crew(text) to anon;
