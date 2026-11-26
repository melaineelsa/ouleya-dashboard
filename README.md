# ATELIER OULEYA — site de gestion partagé

Ce site gère les stocks, les lots, les ventes, les pertes, le chiffre d'affaires et les commandes fournisseurs. Le dashboard R&D y est intégré.
Les données sont stockées dans **Supabase** (gratuit) et le site est hébergé sur **GitHub Pages** (gratuit).

## Contenu

| Fichier | Rôle |
|---|---|
| `index.html` | L'application (Accueil, Stocks, Lots, Ventes & pertes, Commandes, Dashboard R&D) |
| `config.js` | L'adresse et la clé publique de votre projet Supabase |
| `schema.sql` | Les tables, la sécurité (accès réservé à vos 2 courriels) et les matières de départ |
| `dashboard.html` | Le dashboard R&D v15 (formules, fournisseurs, coûts). **Pas sur GitHub** : il est gardé dans le stockage privé de Supabase (voir étape 1.6) |

Avant de configurer quoi que ce soit, ouvrez `index.html` dans un navigateur : le site tourne en **mode démo**, avec des données gardées dans ce navigateur seulement.

## Mise en ligne (environ 20 min)

### 1. Supabase
1. Créez un compte sur https://supabase.com, puis cliquez sur **New project** (région : Canada Central).
2. Ouvrez `schema.sql` et remplacez les 2 courriels de la section 1 par le vôtre et celui de votre sœur.
3. Dans Supabase, allez dans **SQL Editor**, cliquez sur **New query**, collez tout le contenu de `schema.sql` et cliquez sur **Run**.
4. Allez dans **Authentication → URL Configuration** et mettez l'adresse de votre site GitHub Pages (étape 2) dans *Site URL* et dans *Redirect URLs*.
3b. Toujours dans **SQL Editor**, faites une nouvelle requête avec le contenu de votre fichier privé `formules-privees.sql` (sur votre ordinateur seulement) et cliquez sur **Run**.
5. Allez dans **Project Settings → API**, copiez *Project URL* et la clé *anon public*, et collez-les dans `config.js`.
6. Allez dans **Storage**, ouvrez le bucket **prive** (créé par `schema.sql`), cliquez sur **Upload file** et déposez `dashboard.html`. Pour mettre à jour le dashboard plus tard, redéposez le fichier au même endroit (option *Overwrite*).

### 2. GitHub Pages
1. Créez un dépôt (par exemple `ouleya`) et déposez-y `index.html`, `config.js`, `schema.sql` et `README.md` (pas `dashboard.html`, exclu par `.gitignore`).
2. Allez dans **Settings → Pages**, choisissez *Deploy from a branch*, puis `main` et `/ (root)`.
3. Le site sera à l'adresse `https://<votre-compte>.github.io/ouleya/`.

### 3. Connexion
Chacune entre son courriel sur le site et reçoit un lien de connexion par courriel. Un courriel qui n'est pas dans `allowed_emails` peut se connecter, mais ne voit aucune donnée.

## ⚠️ Confidentialité
- **Les données** (stocks, ventes, commandes) sont protégées : seules vos 2 adresses y ont accès (règles RLS de Supabase).
- **Les formules** ne sont pas sur GitHub. Elles sont dans la table protégée `formulas` de Supabase. Vous les gardez dans 2 fichiers privés sur votre ordinateur : `formules-privees.sql` (pour Supabase) et `formules.js` (pour le mode démo). Ces 2 fichiers sont exclus de GitHub par `.gitignore`.
- **Le dashboard R&D** (`dashboard.html`) n'est pas sur GitHub. Il est stocké dans le bucket privé `prive` de Supabase, et l'onglet « Dashboard R&D » ne le télécharge qu'après connexion avec l'un de vos 2 courriels.
- **Les autres fichiers du site** (`index.html`, `config.js`, `schema.sql`) sont publics sur GitHub et GitHub Pages.

## Fonctionnement
- **Lots** : à l'enregistrement d'un lot, le site calcule les grammes de chaque matière selon la formule et **les déduit du stock**. Un aperçu avant l'enregistrement signale les stocks insuffisants.
- **Stocks** : pour une réception, entrez `+4000` pour 4 kg. Pour une perte, entrez une quantité. Chaque mouvement est tracé avec la date et l'auteure.
- **Commandes** : le passage au statut « Reçue » inscrit la date de réception. Ajoutez ensuite les quantités dans Stocks.
- **Accueil** : CA du mois et CA total, marge brute (CA − frais − pertes), matières sous le seuil, commandes en cours, lots en test (avec une alerte à 6 semaines).
- **Temps réel** : quand votre sœur ajoute une vente, votre écran se met à jour tout seul.
- **Nouvelle formule** : ajoutez une ligne dans `formules-privees.sql` (en utilisant les clés des matières : `shea`, `calendula`…) et relancez-le dans le SQL Editor de Supabase. Pour le mode démo, ajoutez-la aussi dans `formules.js`. Rechargez ensuite le site.
