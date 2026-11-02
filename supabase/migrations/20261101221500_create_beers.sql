-- 1 Million Chinese Beers : table des bières
-- Une ligne = une bière. Rien n'est jamais effacé : une bière retirée a juste deleted_at rempli.

create table if not exists public.beers (
  id         uuid primary key,                        -- généré par le téléphone (évite les doublons en cas de réseau capricieux)
  who        text not null check (who in ('alex','louis','felix','pilou','noah','paulin')),
  brand      text not null default 'biere',           -- 'biere' = pas de marque choisie
  at         bigint not null,                         -- heure de la bière, en millisecondes (horloge du téléphone)
  created_at timestamptz not null default now()       -- heure d'arrivée sur le serveur
);

alter table public.beers enable row level security;

-- Tout le monde peut lire (le classement est public), personne n'écrit directement :
-- les ajouts et retraits passent par les fonctions add_beer / remove_beer (voir migration suivante).
drop policy if exists "lecture" on public.beers;
create policy "lecture" on public.beers for select to anon using (true);
grant select on public.beers to anon;
