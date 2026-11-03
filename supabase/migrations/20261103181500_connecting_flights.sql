-- Vols de correspondance à Bahreïn : 2e leg = 2e fenêtre airport beer (alertes push comprises).
insert into public.flights(code, dep, tz, who) values
  ('GF124', '2026-11-03 22:30+03', 'Asia/Bahrain', array['felix','paulin','pilou']),
  ('GF019', '2026-11-19 01:20+03', 'Asia/Bahrain', array['felix','paulin'])
on conflict (code) do update set dep = excluded.dep, tz = excluded.tz, who = excluded.who;
