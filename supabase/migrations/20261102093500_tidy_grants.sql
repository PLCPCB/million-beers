-- Nettoyage : retire les droits donnés par défaut aux nouvelles tables et dont le site n'a pas besoin

revoke truncate, references, trigger on public.beers from anon, authenticated;
