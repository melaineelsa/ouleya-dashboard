-- =====================================================================
-- ATELIER OULEYA — schéma Supabase
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- Remplacez les deux courriels à la section 1 AVANT d'exécuter.
-- =====================================================================

-- 1. Qui a le droit d'accéder (vous deux seulement) -------------------
create table if not exists allowed_emails (email text primary key);
insert into allowed_emails (email) values
  ('VOTRE_COURRIEL@exemple.com'),
  ('COURRIEL_DE_VOTRE_SOEUR@exemple.com')
on conflict do nothing;

create or replace function is_team() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from allowed_emails
                 where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- 2. Matières premières & stock -------------------------------------
create table if not exists ingredients (
  id            bigint generated always as identity primary key,
  key           text unique not null,          -- identifiant utilisé par les formules
  name          text not null,
  unit          text not null default 'g',
  qty           numeric not null default 0,     -- stock actuel
  alert_at      numeric not null default 0,     -- seuil d'alerte
  supplier      text,
  cost_per_unit numeric default 0,              -- $ par g (ou par unité)
  updated_at    timestamptz default now()
);

create table if not exists stock_movements (
  id            bigint generated always as identity primary key,
  ingredient_id bigint references ingredients(id) on delete cascade,
  delta         numeric not null,               -- + entrée, − sortie
  reason        text,                           -- 'lot', 'réception', 'perte', 'ajustement'
  ref           text,                           -- n° de lot, n° de commande…
  created_by    text default (auth.jwt() ->> 'email'),
  created_at    timestamptz default now()
);

-- 2b. Formules (privées) ---------------------------------------------
-- La table est vide ici : remplissez-la avec votre fichier privé formules-privees.sql
-- (gardé sur votre ordinateur, jamais sur GitHub).
create table if not exists formulas (
  key   text primary key,                 -- identifiant (sya, jolie…)
  name  text not null,
  code  text not null,                    -- préfixe du n° de lot (SYA, JK…)
  sort  integer default 0,
  items jsonb not null                    -- {"cle_matiere": pourcentage, …}
);

-- 3. Lots & stabilité ------------------------------------------------
create table if not exists lots (
  id          bigint generated always as identity primary key,
  code        text unique not null,
  made_on     date not null,
  formula     text not null,
  weight_g    numeric not null,
  method      text,
  fill_g      numeric,
  pots        integer,
  stability   text default 'En test',
  notes       text,
  created_by  text default (auth.jwt() ->> 'email'),
  created_at  timestamptz default now()
);

-- 4. Ventes & pertes -------------------------------------------------
create table if not exists sales (
  id          bigint generated always as identity primary key,
  sold_on     date not null default current_date,
  product     text not null,
  format      text,
  qty         integer not null default 1,
  unit_price  numeric not null default 0,
  fees        numeric not null default 0,       -- frais de paiement, livraison payée…
  channel     text,                             -- proches, Facebook, marché…
  lot_code    text,
  notes       text,
  created_by  text default (auth.jwt() ->> 'email'),
  created_at  timestamptz default now()
);

create table if not exists losses (
  id          bigint generated always as identity primary key,
  lost_on     date not null default current_date,
  item        text not null,                    -- produit fini ou matière
  qty         numeric not null default 1,
  unit        text default 'pot',
  cost        numeric not null default 0,       -- valeur perdue en $
  reason      text,                             -- grains, casse, échantillon offert…
  notes       text,
  created_by  text default (auth.jwt() ->> 'email'),
  created_at  timestamptz default now()
);

-- 5. Commandes fournisseurs -----------------------------------------
create table if not exists orders (
  id           bigint generated always as identity primary key,
  supplier     text not null,
  items        text not null,
  amount       numeric default 0,
  status       text not null default 'À commander', -- À commander, Commandée, Expédiée, Reçue, Annulée
  ordered_on   date,
  expected_on  date,
  received_on  date,
  notes        text,
  created_by   text default (auth.jwt() ->> 'email'),
  created_at   timestamptz default now()
);

-- 6. Sécurité : seules vous deux pouvez lire / écrire ----------------
do $$
declare t text;
begin
  foreach t in array array['formulas','ingredients','stock_movements','lots','sales','losses','orders'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists team_all on %I', t);
    execute format('create policy team_all on %I for all to authenticated using (is_team()) with check (is_team())', t);
  end loop;
end $$;
alter table allowed_emails enable row level security;  -- aucune policy : invisible depuis le site

-- 6b. Fichiers privés (dashboard.html) : bucket Storage réservé à vous deux
-- Après avoir exécuté ce script : Storage > prive > Upload file > dashboard.html
insert into storage.buckets (id, name, public) values ('prive', 'prive', false)
on conflict (id) do nothing;
drop policy if exists "equipe lit prive" on storage.objects;
create policy "equipe lit prive" on storage.objects for select to authenticated
  using (bucket_id = 'prive' and public.is_team());

-- 7. Fabrication d'un lot : enregistre le lot ET déduit les matières --
--    usage = [{"key":"shea","grams":195}, …]
create or replace function create_lot(lot jsonb, usage jsonb)
returns lots language plpgsql security invoker set search_path = public as $$
declare
  new_lot lots;
  u jsonb;
  ing ingredients;
begin
  if not is_team() then raise exception 'Accès refusé'; end if;
  insert into lots (code, made_on, formula, weight_g, method, fill_g, pots, notes)
  values (lot->>'code', (lot->>'made_on')::date, lot->>'formula', (lot->>'weight_g')::numeric,
          lot->>'method', nullif(lot->>'fill_g','')::numeric, nullif(lot->>'pots','')::int, lot->>'notes')
  returning * into new_lot;

  for u in select * from jsonb_array_elements(usage) loop
    select * into ing from ingredients where key = u->>'key';
    if found then
      update ingredients set qty = qty - (u->>'grams')::numeric, updated_at = now() where id = ing.id;
      insert into stock_movements (ingredient_id, delta, reason, ref)
      values (ing.id, -(u->>'grams')::numeric, 'lot', new_lot.code);
    end if;
  end loop;
  return new_lot;
end $$;

-- Mouvement de stock manuel (réception, perte, ajustement)
create or replace function move_stock(p_ingredient bigint, p_delta numeric, p_reason text, p_ref text)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if not is_team() then raise exception 'Accès refusé'; end if;
  update ingredients set qty = qty + p_delta, updated_at = now() where id = p_ingredient;
  insert into stock_movements (ingredient_id, delta, reason, ref) values (p_ingredient, p_delta, p_reason, p_ref);
end $$;

-- 8. Matières premières de départ (stock à 0 : saisissez vos réceptions)
insert into ingredients (key, name, unit, alert_at, supplier) values
  ('shea',          'Beurre de karité brut (Burkina Faso)', 'g', 800, 'Karité Delapointe'),
  ('calendula',     'Macérât de calendula',                 'g', 150, 'ONESOAK'),
  ('almond',        'Huile d''amande douce',                'g', 120, 'ONESOAK'),
  ('oat',           'Huile d''avoine',                      'g', 50,  'Les Âmes Fleurs'),
  ('jojoba',        'Huile de jojoba',                      'g', 40,  'ONESOAK'),
  ('castor',        'Huile de ricin',                       'g', 40,  'ONESOAK'),
  ('baobab',        'Huile de baobab',                      'g', 40,  'ONESOAK'),
  ('avocado',       'Huile d''avocat',                      'g', 40,  null),
  ('grapeseed',     'Huile de pépins de raisin',            'g', 100, 'ONESOAK'),
  ('arrowroot',     'Amidon d''arrow-root',                 'g', 20,  'ONESOAK'),
  ('vite',          'Vitamine E (tocophérol)',              'g', 5,   'ONESOAK'),
  ('frag_mango',    'Fragrance mangue',                     'g', 3,   'ONESOAK'),
  ('frag_hibiscus', 'Fragrance hibiscus & goyave',          'g', 3,   'ONESOAK'),
  ('frag_vanilla',  'Fragrance vanille',                    'g', 3,   'ONESOAK'),
  ('frag_soft',     'Fragrance douce (capillaire)',         'g', 3,   'ONESOAK'),
  ('eo_ginger',     'Huile essentielle de gingembre',       'g', 2,   'ONESOAK')
on conflict (key) do nothing;

-- 9. Mise à jour en direct entre vous deux (Realtime)
alter publication supabase_realtime add table ingredients, stock_movements, lots, sales, losses, orders;
