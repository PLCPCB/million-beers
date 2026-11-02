# Base de données (Supabase)

Ce dossier contient tout le code de la base, dans l'ordre où il a été appliqué.
Il ne contient **pas** le code de la bande, le lien du carnet de voyage, ni les bières elles-mêmes.

## Recréer la base de zéro

1. Créer un projet Supabase, ouvrir **SQL Editor**.
2. Coller puis lancer (**Run**) chaque fichier de `migrations/`, dans l'ordre des noms.
3. Ajouter le code de la bande (à garder hors du dépôt) :
   ```sql
   insert into crew_secret(code) values ('le-code-en-minuscules');
   ```
4. Remettre le lien du carnet de voyage (à garder hors du dépôt) :
   ```sql
   insert into band_links(key, url) values ('carnet', 'https://docs.google.com/...')
   on conflict (key) do update set url = excluded.url;
   ```
5. Si l'adresse du projet ou la clé publique changent, les remplacer dans `index.html` **et** `404.html` (`SB_URL` et `SB_KEY`, en haut du script).
6. Pour remettre des bières sauvegardées : Table Editor → `beers` → Insert → Import data from CSV.

## Commandes utiles

Voir les dernières bières :
```sql
select who, brand,
       to_timestamp(at / 1000) at time zone 'Asia/Shanghai' as heure_biere,
       created_at at time zone 'Asia/Shanghai' as ajoutee_le,
       deleted_at at time zone 'Asia/Shanghai' as retiree_le
from beers order by created_at desc limit 50;
```

Annuler tout ce qui a été ajouté après une heure donnée (heure de Pékin, `+08`) :
```sql
update beers set deleted_at = now()
where created_at > '2026-11-08 14:00+08' and deleted_at is null;
```

Restaurer des bières retirées :
```sql
update beers set deleted_at = null where deleted_at > '2026-11-08 14:00+08';
```

Changer le code de la bande (puis envoyer le nouveau lien `…/million-beers/nouveau-code`) :
```sql
update crew_secret set code = 'nouveau-code';
```

## Sauvegarder les bières

Table Editor → `beers` → **Export → CSV**. À garder sur ton ordi, pas dans ce dépôt (il est public).
