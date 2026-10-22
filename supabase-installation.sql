-- =====================================================================
--  Élevage d'ALB — installation de la base Supabase
--  À coller UNE FOIS dans Supabase › SQL Editor › New query, puis « Run ».
--  Le résultat affiche votre CODE D'ACTIVATION GÉRANT : notez-le.
--  Le script peut être relancé sans risque (il ne supprime aucune donnée).
-- =====================================================================

-- ---------- Tables ----------
create table if not exists public.config (
  id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.proprietaires (
  id text primary key, user_id uuid unique references auth.users(id) on delete set null,
  invite_code text unique, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.chevaux (
  id text primary key, proprietaire_id text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.cours (
  id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.taches (
  id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.factures (
  id text primary key, proprietaire_id text, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.annonces (
  id text primary key, data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table if not exists public.messages (
  id text primary key, proprietaire_id text not null, data jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table if not exists public.depenses (
  id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.profils (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('gerant','client','parent')), proprietaire_id text);
create table if not exists public.secrets (k text primary key, v text not null);

insert into public.secrets(k, v)
  values ('code_gerant', upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10)))
  on conflict (k) do nothing;

create index if not exists chevaux_prop_idx on public.chevaux(proprietaire_id);
create index if not exists factures_prop_idx on public.factures(proprietaire_id);
create index if not exists messages_prop_idx on public.messages(proprietaire_id, created_at);

-- ---------- Fonctions d'accès ----------
create or replace function public.est_gerant() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from profils where user_id = auth.uid() and role = 'gerant') $$;

create or replace function public.mon_proprio() returns text
  language sql stable security definer set search_path = public as $$
  select proprietaire_id from profils where user_id = auth.uid() and role = 'client' $$;

create or replace function public.est_membre() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from profils where user_id = auth.uid()) $$;

create or replace function public.mon_profil() returns json
  language sql stable security definer set search_path = public as $$
  select json_build_object('role', role, 'proprietaire_id', proprietaire_id)
  from profils where user_id = auth.uid() $$;

-- Relie le compte connecté à l'écurie grâce à un code d'activation
create or replace function public.lier_compte(p_code text) returns json
  language plpgsql security definer set search_path = public as $$
declare v_code text := upper(trim(coalesce(p_code, ''))); v_prop text;
begin
  if auth.uid() is null then raise exception 'Connectez-vous d''abord.'; end if;
  if exists(select 1 from profils where user_id = auth.uid()) then return mon_profil(); end if;
  if v_code = (select v from secrets where k = 'code_gerant') then
    insert into profils(user_id, role) values (auth.uid(), 'gerant');
    return mon_profil();
  end if;
  select id into v_prop from proprietaires where upper(invite_code) = v_code and user_id is null limit 1;
  if v_prop is null then raise exception 'Code d''activation inconnu ou déjà utilisé.'; end if;
  update proprietaires set user_id = auth.uid(), invite_code = null where id = v_prop;
  insert into profils(user_id, role, proprietaire_id) values (auth.uid(), 'client', v_prop);
  return mon_profil();
end $$;

-- Réservation d'un cours par un client (contrôle des places)
create or replace function public.reserver_cours(p_id text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); d jsonb; ins jsonb; v_debut timestamp;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  select data into d from cours where id = p_id for update;
  if d is null then raise exception 'Cours introuvable.'; end if;
  if coalesce((d->>'annule')::boolean, false) then raise exception 'Ce cours est annulé.'; end if;
  ins := coalesce(d->'inscrits', '[]'::jsonb);
  if ins ? v_prop then return d; end if;
  v_debut := ((d->>'date') || ' ' || coalesce(d->>'heure', '00:00'))::timestamp;
  if v_debut < (now() at time zone 'Europe/Paris') then raise exception 'Ce cours est déjà passé.'; end if;
  if jsonb_array_length(ins) >= coalesce((d->>'places')::int, 1) then raise exception 'Ce cours est complet.'; end if;
  d := jsonb_set(d, '{inscrits}', ins || to_jsonb(v_prop));
  update cours set data = d, updated_at = now() where id = p_id;
  return d;
end $$;

-- Annulation par un client (délai minimum réglé par le gérant, 24 h par défaut)
create or replace function public.annuler_cours(p_id text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); d jsonb; v_debut timestamp; v_delai int;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  select data into d from cours where id = p_id for update;
  if d is null then raise exception 'Cours introuvable.'; end if;
  select coalesce((data->>'annulHeures')::int, 24) into v_delai from config where id = 'main';
  v_delai := coalesce(v_delai, 24);
  v_debut := ((d->>'date') || ' ' || coalesce(d->>'heure', '00:00'))::timestamp;
  if v_debut - (now() at time zone 'Europe/Paris') < make_interval(hours => v_delai) then
    raise exception 'Annulation impossible moins de % h avant le cours : contactez le gérant.', v_delai;
  end if;
  d := jsonb_set(d, '{inscrits}', coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(d->'inscrits', '[]'::jsonb)) x where x <> to_jsonb(v_prop)), '[]'::jsonb));
  update cours set data = d, updated_at = now() where id = p_id;
  return d;
end $$;

grant execute on function public.lier_compte(text), public.reserver_cours(text), public.annuler_cours(text), public.mon_profil() to authenticated;

-- ---------- Règles d'accès (RLS) ----------
alter table public.config enable row level security;
alter table public.proprietaires enable row level security;
alter table public.chevaux enable row level security;
alter table public.cours enable row level security;
alter table public.taches enable row level security;
alter table public.factures enable row level security;
alter table public.annonces enable row level security;
alter table public.messages enable row level security;
alter table public.depenses enable row level security;
alter table public.profils enable row level security;
alter table public.secrets enable row level security;  -- aucune règle : illisible depuis l'appli

do $$ declare t text; begin
  foreach t in array array['config','proprietaires','chevaux','cours','taches','factures','annonces','messages','depenses'] loop
    execute format('drop policy if exists "gerant tout" on public.%I', t);
    execute format('create policy "gerant tout" on public.%I for all to authenticated using ((select public.est_gerant())) with check ((select public.est_gerant()))', t);
  end loop;
end $$;

drop policy if exists "membre lit config" on public.config;
create policy "membre lit config" on public.config for select to authenticated using ((select public.est_membre()));
drop policy if exists "client lit sa fiche" on public.proprietaires;
create policy "client lit sa fiche" on public.proprietaires for select to authenticated using (id = (select public.mon_proprio()));
drop policy if exists "client lit ses chevaux" on public.chevaux;
create policy "client lit ses chevaux" on public.chevaux for select to authenticated using (proprietaire_id = (select public.mon_proprio()));
drop policy if exists "membre lit les cours" on public.cours;
create policy "membre lit les cours" on public.cours for select to authenticated using ((select public.est_membre()));
drop policy if exists "client lit ses factures" on public.factures;
create policy "client lit ses factures" on public.factures for select to authenticated using (proprietaire_id = (select public.mon_proprio()));
drop policy if exists "membre lit les annonces" on public.annonces;
create policy "membre lit les annonces" on public.annonces for select to authenticated using ((select public.est_membre()));
drop policy if exists "client lit ses messages" on public.messages;
create policy "client lit ses messages" on public.messages for select to authenticated using (proprietaire_id = (select public.mon_proprio()));
drop policy if exists "client écrit au gérant" on public.messages;
create policy "client écrit au gérant" on public.messages for insert to authenticated
  with check (proprietaire_id = (select public.mon_proprio()) and data->>'de' = 'client');
drop policy if exists "client marque lu" on public.messages;
create or replace function public.marquer_lus() returns void
  language sql security definer set search_path = public as $$
  update messages set data = jsonb_set(data, '{lu}', 'true'::jsonb)
  where proprietaire_id = mon_proprio() and data->>'de' = 'gerant' and coalesce((data->>'lu')::boolean, false) = false $$;
grant execute on function public.marquer_lus() to authenticated;
drop policy if exists "lit son profil" on public.profils;
create policy "lit son profil" on public.profils for select to authenticated using (user_id = (select auth.uid()) or (select public.est_gerant()));

-- Le propriétaire (ou le cavalier à qui le cheval est confié) note un soin fait ou un rappel
create or replace function public.ajouter_soin(p_cheval text, p_soin jsonb) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); d jsonb; s jsonb; v_date text;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  select data into d from chevaux c where c.id = p_cheval and (c.proprietaire_id = v_prop or exists (
      select 1 from jsonb_array_elements(coalesce(c.data->'cavaliers','[]'::jsonb)) a
      where a->>'proprietaireId' = v_prop and coalesce(nullif(a->>'fin',''),'9999-12-31') >= to_char(now() at time zone 'Europe/Paris','YYYY-MM-DD')))
    for update;
  if d is null then raise exception 'Ce cheval ne vous est pas rattaché.'; end if;
  v_date := coalesce(nullif(p_soin->>'date',''), to_char(now() at time zone 'Europe/Paris','YYYY-MM-DD'));
  if v_date !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Date invalide.'; end if;
  s := jsonb_build_object('id', left(coalesce(p_soin->>'id', md5(random()::text)), 20), 'type', left(coalesce(p_soin->>'type','Autre'), 60),
        'date', v_date, 'note', left(coalesce(p_soin->>'note',''), 200), 'par', 'client',
        'fait', v_date <= to_char(now() at time zone 'Europe/Paris','YYYY-MM-DD'));
  if coalesce(p_soin->>'produit','') <> '' then s := s || jsonb_build_object('produit', left(p_soin->>'produit', 80)); end if;
  d := jsonb_set(d, '{soins}', coalesce(d->'soins','[]'::jsonb) || jsonb_build_array(s));
  update chevaux set data = d, updated_at = now() where id = p_cheval;
  return d;
end $$;

-- Monte libre réservée par un cavalier (créneau visible dans le planning)
create or replace function public.declarer_monte(p_date text, p_heure text, p_duree int, p_lieu text, p_cheval text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); v_id text := 'm' || substr(md5(random()::text || clock_timestamp()::text), 1, 9); v_nom text; d jsonb;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  if p_date !~ '^\d{4}-\d{2}-\d{2}$' or p_heure !~ '^\d{2}:\d{2}$' then raise exception 'Date ou heure invalide.'; end if;
  if (p_date || ' ' || p_heure)::timestamp < (now() at time zone 'Europe/Paris') then raise exception 'Choisissez un créneau à venir.'; end if;
  select split_part(coalesce(data->>'nom','Cavalier'),' ',1) into v_nom from proprietaires where id = v_prop;
  d := jsonb_build_object('type','monte','titre','Monte libre · ' || coalesce(v_nom,'Cavalier'),'date',p_date,'heure',p_heure,
        'duree', least(greatest(coalesce(p_duree,60),15),240),'lieu', left(coalesce(p_lieu,'Carrière'),40),'places',1,'prix',0,
        'inscrits', jsonb_build_array(v_prop),'par',v_prop,
        'montures', case when coalesce(p_cheval,'') <> '' then jsonb_build_object(v_prop, left(p_cheval,40)) else '{}'::jsonb end);
  insert into cours(id, data) values (v_id, d);
  return jsonb_build_object('id', v_id, 'data', d || jsonb_build_object('id', v_id));
end $$;

-- Retrait d'une monte libre par son auteur (le créneau est marqué retiré)
create or replace function public.supprimer_monte(p_id text) returns boolean
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); n int;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  update cours set data = data || '{"retire":true,"inscrits":[]}'::jsonb, updated_at = now()
    where id = p_id and data->>'type' = 'monte' and data->>'par' = v_prop;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Créneau introuvable.'; end if;
  return true;
end $$;
revoke execute on function public.ajouter_soin(text,jsonb), public.declarer_monte(text,text,int,text,text), public.supprimer_monte(text) from public, anon;
grant execute on function public.ajouter_soin(text,jsonb), public.declarer_monte(text,text,int,text,text), public.supprimer_monte(text) to authenticated;

-- Le client indique s'il sera présent ou absent à un cours où il est inscrit
create or replace function public.repondre_presence(p_id text, p_rep text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); d jsonb;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  if p_rep not in ('oui','non') then raise exception 'Réponse invalide.'; end if;
  select data into d from cours where id = p_id for update;
  if d is null then raise exception 'Cours introuvable.'; end if;
  if not coalesce(d->'inscrits','[]'::jsonb) ? v_prop then raise exception 'Vous n''êtes pas inscrit à ce cours.'; end if;
  d := jsonb_set(d, '{presences}', coalesce(d->'presences','{}'::jsonb) || jsonb_build_object(v_prop, p_rep));
  update cours set data = d, updated_at = now() where id = p_id;
  return d;
end $$;
revoke execute on function public.repondre_presence(text,text) from public, anon;
grant execute on function public.repondre_presence(text,text) to authenticated;

-- Le client modifie lui-même ses coordonnées (téléphone, e-mail, adresse, licence, assurance)
create or replace function public.modifier_coordonnees(p_tel text, p_email text, p_adresse text, p_licence text, p_rc text) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare v_prop text := mon_proprio(); d jsonb;
begin
  if v_prop is null then raise exception 'Compte client non activé.'; end if;
  update proprietaires set data = data || jsonb_build_object('tel', left(coalesce(p_tel,''),40), 'email', left(coalesce(p_email,''),120), 'adresse', left(coalesce(p_adresse,''),400), 'licence', left(coalesce(p_licence,''),40), 'rcFin', left(coalesce(p_rc,''),10)), updated_at = now()
    where id = v_prop returning data into d;
  return d;
end $$;
revoke execute on function public.modifier_coordonnees(text,text,text,text,text) from public, anon;
grant execute on function public.modifier_coordonnees(text,text,text,text,text) to authenticated;

-- Un cavalier (demi-pension, location…) voit le cheval qui lui est confié
drop policy if exists "cavalier lit les chevaux confiés" on public.chevaux;
create policy "cavalier lit les chevaux confiés" on public.chevaux for select to authenticated
  using (exists (select 1 from jsonb_array_elements(coalesce(data->'cavaliers','[]'::jsonb)) a
                 where a->>'proprietaireId' = (select public.mon_proprio())
                   and coalesce(nullif(a->>'fin',''),'9999-12-31') >= to_char(now() at time zone 'Europe/Paris','YYYY-MM-DD')));

-- ---------- Notifications (cloche de l'appli + téléphones) ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  titre text not null, texte text, lien text,
  lu boolean not null default false,
  created_at timestamptz not null default now());
create index if not exists notifications_user on public.notifications(user_id, created_at desc);
create table if not exists public.push_subs (
  endpoint text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  sub jsonb not null,
  created_at timestamptz not null default now());
alter table public.push_subs add column if not exists meteo boolean not null default true;  -- météo du matin sur ce téléphone
insert into public.secrets(k, v) values ('cron_key', encode(gen_random_bytes(24), 'hex')) on conflict (k) do nothing;
alter table public.notifications enable row level security;
alter table public.push_subs enable row level security;
-- Les cavaliers voient tous les chevaux de l'écurie, et les tâches du jour rendues visibles par le gérant.
drop policy if exists "membre lit tous les chevaux" on public.chevaux;
create policy "membre lit tous les chevaux" on public.chevaux for select to authenticated using ((select public.est_membre()));
drop policy if exists "membre lit les taches visibles" on public.taches;
create policy "membre lit les taches visibles" on public.taches for select to authenticated using ((select public.est_membre()) and coalesce((data->>'visible')::boolean,false));
drop policy if exists "lit ses notifications" on public.notifications;
create policy "lit ses notifications" on public.notifications for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "marque ses notifications" on public.notifications;
create policy "marque ses notifications" on public.notifications for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "gere ses abonnements" on public.push_subs;
create policy "gere ses abonnements" on public.push_subs for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, update on public.notifications to authenticated;
grant select, insert, update, delete on public.push_subs to authenticated;
revoke all on public.notifications, public.push_subs from anon;

-- ---------- Stockage des justificatifs (photos, PDF) ----------
insert into storage.buckets (id, name, public) values ('pieces', 'pieces', false) on conflict (id) do nothing;
drop policy if exists "pieces gerant" on storage.objects;
create policy "pieces gerant" on storage.objects for all to authenticated
  using (bucket_id = 'pieces' and (select public.est_gerant())) with check (bucket_id = 'pieces' and (select public.est_gerant()));
drop policy if exists "pieces client lecture" on storage.objects;
create policy "pieces client lecture" on storage.objects for select to authenticated
  using (bucket_id = 'pieces' and (storage.foldername(name))[1] = (select public.mon_proprio()));

-- ---------- Droits d'accès de l'appli (les règles RLS ci-dessus filtrent les lignes) ----------
revoke execute on function public.lier_compte(text), public.reserver_cours(text), public.annuler_cours(text), public.mon_profil(), public.marquer_lus() from public, anon;
revoke execute on function public.est_gerant(), public.est_membre(), public.mon_proprio() from public, anon;
grant execute on function public.lier_compte(text), public.reserver_cours(text), public.annuler_cours(text), public.mon_profil(), public.marquer_lus() to authenticated;
grant execute on function public.est_gerant(), public.mon_proprio(), public.est_membre() to authenticated;
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.config, public.proprietaires, public.chevaux, public.cours, public.taches, public.factures, public.annonces, public.messages, public.depenses to authenticated;
grant select on public.profils to authenticated;
revoke all on public.secrets from anon, authenticated;
revoke all on public.config, public.proprietaires, public.chevaux, public.cours, public.taches, public.factures, public.annonces, public.messages, public.depenses, public.profils from anon;

-- ---------- Votre code d'activation gérant ----------
select v as "CODE D'ACTIVATION GÉRANT (à noter)" from public.secrets where k = 'code_gerant';

-- ---------- Météo du matin (7 h, heure de Paris) ----------
-- À lancer une fois après avoir déployé la fonction « notifier ». Remplacez VOTRE-PROJET et VOTRE-CLE-ANON
-- (Project Settings › API). La tâche tourne à 5 h et 6 h UTC ; la fonction n'envoie qu'à 7 h à Paris (été comme hiver).
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
-- select cron.schedule('meteo-du-matin', '0 5,6 * * *', $job$
--   select net.http_post(url := 'https://VOTRE-PROJET.supabase.co/functions/v1/notifier', body := '{"action":"matin"}'::jsonb,
--     headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer VOTRE-CLE-ANON',
--       'x-cron-key', (select v from public.secrets where k = 'cron_key')), timeout_milliseconds := 30000);
-- $job$);


-- ============ Compte parent pour les cavaliers mineurs ============
alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check check (role = any (array['gerant'::text, 'client'::text, 'parent'::text]));
alter table public.proprietaires add column if not exists invite_code_parent text;
alter table public.proprietaires add column if not exists parent_user_id uuid;
create or replace function public.mon_proprio() returns text language sql stable security definer set search_path to 'public' as $$
  select proprietaire_id from profils where user_id = auth.uid() and role in ('client','parent') $$;
create or replace function public.enfant_restreint() returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists(select 1 from profils pr join proprietaires p on p.id = pr.proprietaire_id
    where pr.user_id = auth.uid() and pr.role = 'client'
      and coalesce((p.data->>'autonome')::boolean, false) = false
      and (coalesce((p.data->>'mineur')::boolean, false)
           or (coalesce(p.data->>'naissance','') ~ '^\d{4}-\d{2}-\d{2}$' and (p.data->>'naissance')::date > (now() at time zone 'Europe/Paris')::date - interval '18 years'))) $$;
revoke execute on function public.enfant_restreint() from anon;
create or replace function public.lier_compte(p_code text) returns json language plpgsql security definer set search_path to 'public' as $function$
declare v_code text := upper(trim(coalesce(p_code, ''))); v_prop text;
begin
  if auth.uid() is null then raise exception 'Connectez-vous d''abord.'; end if;
  if exists(select 1 from profils where user_id = auth.uid()) then return mon_profil(); end if;
  if v_code = (select v from secrets where k = 'code_gerant') then insert into profils(user_id, role) values (auth.uid(), 'gerant'); return mon_profil(); end if;
  select id into v_prop from proprietaires where upper(invite_code) = v_code and user_id is null limit 1;
  if v_prop is not null then
    update proprietaires set user_id = auth.uid(), invite_code = null where id = v_prop;
    insert into profils(user_id, role, proprietaire_id) values (auth.uid(), 'client', v_prop); return mon_profil();
  end if;
  select id into v_prop from proprietaires where upper(invite_code_parent) = v_code and parent_user_id is null limit 1;
  if v_prop is not null then
    update proprietaires set parent_user_id = auth.uid(), invite_code_parent = null where id = v_prop;
    insert into profils(user_id, role, proprietaire_id) values (auth.uid(), 'parent', v_prop); return mon_profil();
  end if;
  raise exception 'Code d''activation inconnu ou déjà utilisé.';
end $function$;
-- reserver_cours, annuler_cours, modifier_coordonnees et declarer_monte refusent l'action quand enfant_restreint() est vrai
-- (voir la migration « compte_parent » appliquée sur la base en ligne).
