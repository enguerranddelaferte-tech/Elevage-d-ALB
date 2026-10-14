-- =====================================================================
--  Gestion d'Écurie — installation de la base Supabase
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
create table if not exists public.profils (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('gerant','client')), proprietaire_id text);
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
alter table public.profils enable row level security;
alter table public.secrets enable row level security;  -- aucune règle : illisible depuis l'appli

do $$ declare t text; begin
  foreach t in array array['config','proprietaires','chevaux','cours','taches','factures','annonces','messages'] loop
    execute format('drop policy if exists "gerant tout" on public.%I', t);
    execute format('create policy "gerant tout" on public.%I for all to authenticated using (public.est_gerant()) with check (public.est_gerant())', t);
  end loop;
end $$;

drop policy if exists "membre lit config" on public.config;
create policy "membre lit config" on public.config for select to authenticated using (public.est_membre());
drop policy if exists "client lit sa fiche" on public.proprietaires;
create policy "client lit sa fiche" on public.proprietaires for select to authenticated using (id = public.mon_proprio());
drop policy if exists "client lit ses chevaux" on public.chevaux;
create policy "client lit ses chevaux" on public.chevaux for select to authenticated using (proprietaire_id = public.mon_proprio());
drop policy if exists "membre lit les cours" on public.cours;
create policy "membre lit les cours" on public.cours for select to authenticated using (public.est_membre());
drop policy if exists "client lit ses factures" on public.factures;
create policy "client lit ses factures" on public.factures for select to authenticated using (proprietaire_id = public.mon_proprio());
drop policy if exists "membre lit les annonces" on public.annonces;
create policy "membre lit les annonces" on public.annonces for select to authenticated using (public.est_membre());
drop policy if exists "client lit ses messages" on public.messages;
create policy "client lit ses messages" on public.messages for select to authenticated using (proprietaire_id = public.mon_proprio());
drop policy if exists "client écrit au gérant" on public.messages;
create policy "client écrit au gérant" on public.messages for insert to authenticated
  with check (proprietaire_id = public.mon_proprio() and data->>'de' = 'client');
drop policy if exists "client marque lu" on public.messages;
create or replace function public.marquer_lus() returns void
  language sql security definer set search_path = public as $$
  update messages set data = jsonb_set(data, '{lu}', 'true'::jsonb)
  where proprietaire_id = mon_proprio() and data->>'de' = 'gerant' and coalesce((data->>'lu')::boolean, false) = false $$;
grant execute on function public.marquer_lus() to authenticated;
drop policy if exists "lit son profil" on public.profils;
create policy "lit son profil" on public.profils for select to authenticated using (user_id = auth.uid() or public.est_gerant());

-- ---------- Stockage des justificatifs (photos, PDF) ----------
insert into storage.buckets (id, name, public) values ('pieces', 'pieces', false) on conflict (id) do nothing;
drop policy if exists "pieces gerant" on storage.objects;
create policy "pieces gerant" on storage.objects for all to authenticated
  using (bucket_id = 'pieces' and public.est_gerant()) with check (bucket_id = 'pieces' and public.est_gerant());
drop policy if exists "pieces client lecture" on storage.objects;
create policy "pieces client lecture" on storage.objects for select to authenticated
  using (bucket_id = 'pieces' and (storage.foldername(name))[1] = public.mon_proprio());

-- ---------- Votre code d'activation gérant ----------
select v as "CODE D'ACTIVATION GÉRANT (à noter)" from public.secrets where k = 'code_gerant';
