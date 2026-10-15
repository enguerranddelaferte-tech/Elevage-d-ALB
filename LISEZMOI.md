# Élevage d'ALB — appli gérant + espace clients

Une seule écurie, deux espaces dans la même appli :
- **Gérant** : chevaux, soins et frais, planning des cours, tâches du jour, factures, propriétaires, annonces, messages.
- **Clients** (propriétaires / cavaliers) : réservation et annulation de cours, fiche de leur cheval, factures, annonces, messagerie avec le gérant.

L'hébergement est gratuit : **GitHub Pages** pour l'appli, **Supabase** pour la base de données partagée.

## Contenu du dossier

- `index.html` : l'application
- `config.js` : l'adresse de votre base Supabase (à remplir, étape 2)
- `supabase-installation.sql` : le script qui crée la base (étape 1)
- `supabase/functions/` : les petits services en ligne (météo, notifications et e-mails)
- `manifest.webmanifest`, `sw.js`, `icons/` : installation sur téléphone et fonctionnement hors ligne

Tant que `config.js` est vide, l'appli fonctionne en **mode démo** : données d'exemple gardées dans le navigateur, et un sélecteur « Voir l'appli comme… » (Réglages) pour tester l'espace d'un client.

## 1. Créer la base Supabase (une fois, 10 minutes)

1. Créez un compte sur https://supabase.com puis **New project**. Région : **Europe (Paris ou Frankfurt)**. Notez le mot de passe de la base.
2. **Authentication › Sign In / Providers › Email** : désactivez **Confirm email**, puis enregistrez.
   (La sécurité repose sur le code d'activation que vous donnez à chaque client. Sans cette option, Supabase devrait envoyer un e-mail à chaque inscription, et son service d'e-mails gratuit est très limité.)
3. **SQL Editor › New query** : collez tout le contenu de `supabase-installation.sql`, puis **Run**.
   Le résultat affiche votre **CODE D'ACTIVATION GÉRANT** : notez-le précieusement.
4. **Project Settings › API** : copiez **Project URL** et la clé **anon public**.

## 2. Relier l'appli à la base

Ouvrez `config.js` et collez les deux valeurs entre les apostrophes :

```js
window.ECURIE_CONFIG = {
  supabaseUrl: 'https://xxxxxxxx.supabase.co',
  supabaseKey: 'eyJhbGciOi...'
};
```

La clé « anon » est prévue pour être publique : ce sont les règles d'accès de la base qui protègent les données (un client ne voit que ses chevaux, ses factures et ses messages).

## 3. Mettre l'appli en ligne avec GitHub Pages

1. Sur https://github.com : **+ › New repository**, nom `ecurie`, **Public**, **Create repository**.
2. **uploading an existing file** : glissez **tout le contenu** du dossier (`index.html`, `config.js`, `sw.js`, `manifest.webmanifest`, le dossier `icons`…). **Commit changes**.
   `index.html` doit être à la racine du dépôt.
3. **Settings › Pages** : Source **Deploy from a branch**, Branch **main** et **/(root)**, **Save**.
4. Après une à deux minutes, l'appli est à l'adresse `https://VOTRE-PSEUDO.github.io/ecurie/`.

## 4. Premier lancement du gérant

1. Ouvrez l'adresse, touchez **Première connexion : créer mon compte**.
2. Saisissez votre e-mail, un mot de passe et le **code d'activation gérant** (étape 1.3).
3. Renseignez Réglages › **Mon écurie**, les tarifs et le délai d'annulation des cours.
4. Pour reprendre les données d'une version précédente : dans l'ancienne appli, Réglages › Télécharger la sauvegarde, puis ici Réglages › Restaurer.

## 5. Inviter les clients

1. Onglet **Clients** › **+ Propriétaire** : si vous saisissez son e-mail, **l'invitation part automatiquement par e-mail** à l'enregistrement de la fiche (lien de l'appli + code d'activation). Bouton « Envoyer l'invitation par e-mail » pour la renvoyer.
2. Sans e-mail automatique (pas encore configuré) : fiche du client › **Créer un code d'accès** › **Envoyer l'invitation** (SMS, WhatsApp, e-mail…).
3. Le client ouvre le lien, crée son compte avec ce code ; sa fiche affiche ensuite « Compte client activé ». Chaque code ne sert qu'une fois.

## 6. Installer sur le téléphone

- **Android (Chrome)** : bandeau « Installer », ou menu ⋮ › Installer l'application.
- **iPhone (Safari)** : Partager › **Sur l'écran d'accueil**.

## Notifications et e-mails

- **Cloche** en haut de l'écran : toutes les notifications (cours annulé ou modifié, inscription à un cours, nouveau message, annonce, facture). Pastille rouge = non lues.
- **Sur le téléphone, même appli fermée** : chaque personne touche « Activer les notifications » (bandeau d'accueil ou Réglages). Sur iPhone, il faut d'abord installer l'appli sur l'écran d'accueil (iOS 16.4 ou plus récent).
- **Annuler des cours** : Planning › « Annuler les cours de ce jour… » (ou depuis Aujourd'hui), motif en un clic (Piste gelée, Intempéries…). Ou fiche d'un cours › « Annuler ce cours ». Les cavaliers inscrits sont prévenus, le cours n'est plus réservable ni facturé. « Rétablir le cours » prévient aussi.
- Le gérant est prévenu quand un client réserve, annule ou écrit un message.
- **E-mails automatiques** (invitation des clients) : service gratuit **Brevo** (300 e-mails/jour). Créez un compte sur brevo.com, validez l'adresse e-mail de l'écurie comme expéditeur (Senders), créez une clé API (SMTP & API › API Keys), puis dans Supabase › Edge Functions › Secrets ajoutez `BREVO_API_KEY` = votre clé. L'adresse expéditrice est l'e-mail saisi dans Réglages › Mon écurie (ou le secret `EMAIL_FROM`).

## Comptabilité (onglet Compta)

- **Factures préparées d'avance** : à partir du 25, les factures du mois sont créées en brouillon (pensions au prorata des arrivées et départs, cours, frais). Vous vérifiez et vous envoyez. Désactivable dans Réglages.
- **Paiements** : dans une facture, « Enregistrer le paiement » (date et mode : virement, chèque, espèces…).
- **Relances** : les factures en retard apparaissent dans Aujourd'hui et Factures ; « Relancer » envoie le message de relance avec la facture.
- **Avoirs** : sur une facture envoyée, « Créer un avoir » (lignes annulées ou montant libre, avec motif). Numérotation propre AV2026-0001…
- **Dépenses** : achats de l'écurie avec photo du justificatif, catégorie et TVA.
- **TVA** : récapitulatif collectée / déductible / nette si vous êtes assujetti.
- **Pour la comptable** : journaux Excel (CSV) des ventes, encaissements et dépenses, et un **pack comptable .zip** par mois, trimestre ou année (factures et avoirs en PDF, justificatifs, journaux).

## Météo

Sur l'écran Aujourd'hui (gérant) et l'Accueil (clients) : la météo du jour, les 4 prochains jours et des conseils pour les chevaux (gel, nuit fraîche, chaleur, pluie, vent fort, orage). Le gérant choisit la commune avec le bouton « Changer ».
Sources ouvertes, utilisables pour une activité professionnelle : prévisions MET Norway (api.met.no, CC BY 4.0, attribution affichée sous la météo) et recherche de commune geo.api.gouv.fr (licence ouverte Etalab).

## Bon à savoir

- **Offre gratuite Supabase** : 500 Mo de base et 1 Go de fichiers (justificatifs), largement suffisant pour une écurie. Un projet gratuit est mis en pause après 7 jours sans activité ; avec un usage régulier cela n'arrive pas. Sinon, relancez-le d'un clic dans le tableau de bord Supabase : les données sont conservées.
- **Mot de passe oublié** : le lien de réinitialisation est envoyé par e-mail par Supabase (nombre d'e-mails limité sur l'offre gratuite). Le gérant peut aussi supprimer un compte dans Supabase › Authentication › Users, puis recréer un code d'accès au client.
- **Factures** : visibles par le client dès qu'elles sont envoyées ou publiées. Une facture envoyée n'est plus recalculée ni supprimable (numérotation continue).
- **RGPD** : les coordonnées des clients sont stockées en ligne. Informez-les (finalité : gestion de la pension, des cours et de la facturation ; données conservées pendant la relation puis selon les obligations comptables ; droit d'accès et de rectification auprès du gérant).
- **Sauvegarde** : Réglages › Télécharger la sauvegarde, de temps en temps.

## Mettre à jour l'appli

Sur GitHub : **Add file › Upload files**, glissez les nouveaux fichiers (sauf `config.js`, déjà rempli), **Commit changes**. L'appli se met à jour à la prochaine ouverture. Les données, elles, sont dans Supabase et ne sont pas touchées.
